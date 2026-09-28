#import <Cocoa/Cocoa.h>
#import <dlfcn.h>
#import <sys/xattr.h>
#import <unistd.h>

typedef void *hostfxr_handle;

typedef struct hostfxr_initialize_parameters {
    size_t size;
    const char *host_path;
    const char *dotnet_root;
} hostfxr_initialize_parameters;

typedef int32_t (*hostfxr_initialize_for_dotnet_command_line_fn)(
    int argc,
    const char **argv,
    const hostfxr_initialize_parameters *parameters,
    hostfxr_handle *host_context_handle
);

typedef int32_t (*hostfxr_run_app_fn)(hostfxr_handle host_context_handle);
typedef int32_t (*hostfxr_close_fn)(hostfxr_handle host_context_handle);

static int showFailure(NSString *message) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = @"Unora Launcher could not start";
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
    return 1;
}

static void scheduleMenuBranding(void) {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (NSInteger attempt = 0; attempt < 80; attempt++) {
            usleep(100000);
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMenuItem *applicationItem = NSApp.mainMenu.itemArray.firstObject;
                if (!applicationItem) return;

                applicationItem.title = @"Unora Launcher";
                applicationItem.submenu.title = @"Unora Launcher";
                for (NSMenuItem *item in applicationItem.submenu.itemArray) {
                    item.title = [item.title stringByReplacingOccurrencesOfString:@"Avalonia Application"
                                                                       withString:@"Unora Launcher"];
                }
            });
        }
    });
}

static BOOL isVersionName(NSString *name) {
    static NSRegularExpression *expression;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        expression = [NSRegularExpression regularExpressionWithPattern:@"^[0-9]+(\\.[0-9]+){1,3}$"
                                                                options:0
                                                                  error:NULL];
    });
    NSRange whole = NSMakeRange(0, name.length);
    return [expression firstMatchInString:name options:0 range:whole] != nil;
}

static BOOL isCompleteVersion(NSURL *directory) {
    NSFileManager *files = NSFileManager.defaultManager;
    for (NSString *name in @[@"Chaos.Launcher.App.dll", @"Chaos.Launcher.App.deps.json",
                             @"Chaos.Launcher.App.runtimeconfig.json", @"Chaos.Launcher.Core.dll",
                             @"Chaos.Launcher.Platform.dll", @"runtimes/osx/native/libAvaloniaNative.dylib",
                             @"runtimes/osx/native/libSkiaSharp.dylib", @"runtimes/osx/native/libHarfBuzzSharp.dylib"]) {
        BOOL isDirectory = NO;
        NSString *path = [directory URLByAppendingPathComponent:name].path;
        if (![files fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) return NO;
    }
    return YES;
}

static NSURL *newestVersionDirectory(NSURL *versionsDirectory) {
    NSArray<NSURL *> *entries = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:versionsDirectory
      includingPropertiesForKeys:nil
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:NULL];

    NSArray<NSURL *> *versions = [entries filteredArrayUsingPredicate:
        [NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings) {
            return isVersionName(url.lastPathComponent) && isCompleteVersion(url);
        }]];

    return [versions sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
        return [left.lastPathComponent compare:right.lastPathComponent
                                        options:NSNumericSearch];
    }].lastObject;
}

static void clearQuarantineFromNativeLibraries(NSURL *launcherRoot) {
    NSDirectoryEnumerator<NSURL *> *enumerator = [[NSFileManager defaultManager]
        enumeratorAtURL:launcherRoot
 includingPropertiesForKeys:nil
                    options:NSDirectoryEnumerationSkipsHiddenFiles
               errorHandler:nil];

    for (NSURL *url in enumerator) {
        if ([url.pathExtension isEqualToString:@"dylib"]) {
            removexattr(url.fileSystemRepresentation, "com.apple.quarantine", XATTR_NOFOLLOW);
        }
    }
}

static NSURL *launcherDataRoot(void) {
    const char *override = getenv("UNORA_LAUNCHER_HOME");
    if (override && override[0] != '\0') {
        return [NSURL fileURLWithPath:[NSString stringWithUTF8String:override] isDirectory:YES];
    }

    NSURL *applicationSupport = [[[NSFileManager defaultManager]
        URLsForDirectory:NSApplicationSupportDirectory
               inDomains:NSUserDomainMask] firstObject];
    return [applicationSupport URLByAppendingPathComponent:@"Unora Launcher" isDirectory:YES];
}

static void exposeBundledDotnet(NSURL *dotnetRootURL) {
    const char *existingPath = getenv("PATH");
    NSString *path = dotnetRootURL.path;
    if (existingPath && existingPath[0] != '\0') {
        path = [path stringByAppendingFormat:@":%s", existingPath];
    }
    setenv("PATH", path.fileSystemRepresentation, 1);
}

static NSURL *prepareWritableLauncher(NSURL *resourcesURL, NSString *seedVersionName, NSError **error) {
    NSFileManager *files = [NSFileManager defaultManager];
    NSURL *seedRoot = [resourcesURL URLByAppendingPathComponent:@"Launcher" isDirectory:YES];
    NSURL *dataRoot = launcherDataRoot();
    NSURL *launcherRoot = [dataRoot URLByAppendingPathComponent:@"Launcher" isDirectory:YES];
    NSURL *versionsRoot = [launcherRoot URLByAppendingPathComponent:@"versions" isDirectory:YES];
    NSURL *seedVersion = [[seedRoot URLByAppendingPathComponent:@"versions" isDirectory:YES]
        URLByAppendingPathComponent:seedVersionName isDirectory:YES];
    NSURL *installedVersion = [versionsRoot URLByAppendingPathComponent:seedVersionName isDirectory:YES];

    if (![files createDirectoryAtURL:versionsRoot
          withIntermediateDirectories:YES
                           attributes:nil
                                error:error]) {
        return nil;
    }

    if (!isCompleteVersion(installedVersion)) {
        // Copy out of view, then rename so an interrupted copy cannot become active.
        NSURL *staging = [versionsRoot URLByAppendingPathComponent:
            [@".staging-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
        if (![files copyItemAtURL:seedVersion toURL:staging error:error]) {
            [files removeItemAtURL:staging error:NULL];
            return nil;
        }
        if (!isCompleteVersion(staging)) {
            if (error) *error = [NSError errorWithDomain:@"UnoraLauncher" code:1 userInfo:
                @{NSLocalizedDescriptionKey: @"The bundled launcher version is incomplete."}];
            [files removeItemAtURL:staging error:NULL];
            return nil;
        }
        if ([files fileExistsAtPath:installedVersion.path]) {
            // Upstream prunes old entries inside versions/, so recover elsewhere.
            NSURL *recovered = [launcherRoot URLByAppendingPathComponent:@"recovered" isDirectory:YES];
            if (![files createDirectoryAtURL:recovered withIntermediateDirectories:YES attributes:nil error:error]) {
                [files removeItemAtURL:staging error:NULL];
                return nil;
            }
            NSURL *backup = [recovered URLByAppendingPathComponent:
                [seedVersionName stringByAppendingFormat:@"-%@", NSUUID.UUID.UUIDString] isDirectory:YES];
            if (![files moveItemAtURL:installedVersion toURL:backup error:error]) {
                [files removeItemAtURL:staging error:NULL];
                return nil;
            }
        }
        if (![files moveItemAtURL:staging toURL:installedVersion error:error]) {
            [files removeItemAtURL:staging error:NULL];
            return nil;
        }
    }

    NSURL *seedRunner = [seedRoot URLByAppendingPathComponent:@"run.sh"];
    NSURL *installedRunner = [launcherRoot URLByAppendingPathComponent:@"run.sh"];
    if ([files fileExistsAtPath:seedRunner.path] &&
        ![files fileExistsAtPath:installedRunner.path]) {
        [files copyItemAtURL:seedRunner toURL:installedRunner error:NULL];
    }

    clearQuarantineFromNativeLibraries(launcherRoot);
    return launcherRoot;
}

static int firstUserArgument(int argc, const char *argv[], NSURL *managedApp) {
    // Upstream restarts Environment.ProcessPath and passes its managed DLL.
    // This executable is the native host; it already supplies that DLL itself.
    return argc > 1 && strcmp(argv[1], managedApp.fileSystemRepresentation) == 0 ? 2 : 1;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSURL *resourcesURL = NSBundle.mainBundle.resourceURL;
        if (!resourcesURL) {
            return showFailure(@"The app bundle is missing its Resources directory. Please download it again.");
        }

        NSError *prepareError = nil;
        NSString *seedVersionName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"UnoraSeedVersion"];
        if (!isVersionName(seedVersionName ?: @"")) {
            return showFailure(@"The app bundle has an invalid launcher version. Please download it again.");
        }
        NSURL *launcherRoot = prepareWritableLauncher(resourcesURL, seedVersionName, &prepareError);
        if (!launcherRoot) {
            return showFailure([NSString stringWithFormat:
                @"The launcher could not prepare its writable files.\n\n%@",
                prepareError.localizedDescription ?: @"Unknown filesystem error"]);
        }

        NSURL *versionsRoot = [launcherRoot URLByAppendingPathComponent:@"versions" isDirectory:YES];
        NSURL *currentVersion = newestVersionDirectory(versionsRoot);
        if (!currentVersion) {
            return showFailure(@"No complete launcher version was found. Reinstall the app to restore it.");
        }

        NSURL *managedApp = [currentVersion URLByAppendingPathComponent:@"Chaos.Launcher.App.dll"];
        if (![[NSFileManager defaultManager] fileExistsAtPath:managedApp.path]) {
            return showFailure(@"The newest launcher version is incomplete. Reinstall the app to restore it.");
        }
        NSURL *dotnetRootURL = [resourcesURL URLByAppendingPathComponent:@"dotnet" isDirectory:YES];
        NSURL *hostFxrURL = [dotnetRootURL URLByAppendingPathComponent:
            @"host/fxr/10.0.10/libhostfxr.dylib"];
        NSURL *hostExecutableURL = NSBundle.mainBundle.executableURL;

        setenv("DOTNET_ROOT", dotnetRootURL.fileSystemRepresentation, 1);
        setenv("DOTNET_MULTILEVEL_LOOKUP", "0", 1);
        setenv("DOTNET_NOLOGO", "1", 1);
        exposeBundledDotnet(dotnetRootURL);
        if (chdir(launcherRoot.fileSystemRepresentation) != 0) {
            return showFailure(@"The launcher data folder could not be opened.");
        }

        void *hostFxr = dlopen(hostFxrURL.fileSystemRepresentation, RTLD_LAZY | RTLD_LOCAL);
        if (!hostFxr) {
            return showFailure([NSString stringWithFormat:
                @"The bundled .NET runtime could not be loaded.\n\n%s", dlerror()]);
        }

        hostfxr_initialize_for_dotnet_command_line_fn initialize =
            (hostfxr_initialize_for_dotnet_command_line_fn)dlsym(
                hostFxr, "hostfxr_initialize_for_dotnet_command_line");
        hostfxr_run_app_fn runApp =
            (hostfxr_run_app_fn)dlsym(hostFxr, "hostfxr_run_app");
        hostfxr_close_fn closeHost =
            (hostfxr_close_fn)dlsym(hostFxr, "hostfxr_close");

        if (!initialize || !runApp || !closeHost) {
            dlclose(hostFxr);
            return showFailure(@"The bundled .NET runtime is incomplete. Please download the app again.");
        }

        int firstArgument = firstUserArgument(argc, argv, managedApp);
        int managedArgc = 1 + argc - firstArgument;
        const char **managedArgv = calloc((size_t)managedArgc, sizeof(char *));
        managedArgv[0] = managedApp.fileSystemRepresentation;
        for (int index = firstArgument; index < argc; index++) {
            managedArgv[1 + index - firstArgument] = argv[index];
        }

        hostfxr_initialize_parameters parameters = {
            .size = sizeof(hostfxr_initialize_parameters),
            .host_path = hostExecutableURL.fileSystemRepresentation,
            .dotnet_root = dotnetRootURL.fileSystemRepresentation
        };
        hostfxr_handle context = NULL;
        int32_t result = initialize(managedArgc, managedArgv, &parameters, &context);
        free(managedArgv);

        if (result < 0 || !context) {
            dlclose(hostFxr);
            return showFailure([NSString stringWithFormat:
                @"The bundled .NET runtime could not initialize (error 0x%08x).", result]);
        }

        scheduleMenuBranding();
        int32_t exitCode = runApp(context);
        closeHost(context);
        dlclose(hostFxr);
        return exitCode;
    }
}
