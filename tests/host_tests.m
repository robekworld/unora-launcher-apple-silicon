// Exercise real host filesystem behavior without starting the managed UI.
#define main unoraApplicationMain
#import "../macos/UnoraLauncherHost.m"
#undef main

static void check(BOOL condition, NSString *description) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", description.UTF8String);
        exit(1);
    }
    printf("PASS: %s\n", description.UTF8String);
}

static void writeFile(NSURL *root, NSString *name, NSString *text) {
    NSURL *url = [root URLByAppendingPathComponent:name];
    NSError *error = nil;
    BOOL made = [NSFileManager.defaultManager createDirectoryAtURL:[url URLByDeletingLastPathComponent]
        withIntermediateDirectories:YES attributes:nil error:&error];
    if (!made || ![text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        fprintf(stderr, "Fixture error: %s\n", error.localizedDescription.UTF8String);
        exit(1);
    }
}

static void completeVersion(NSURL *root, NSString *name) {
    NSURL *version = [root URLByAppendingPathComponent:name];
    for (NSString *file in @[@"Chaos.Launcher.App.dll", @"Chaos.Launcher.App.deps.json",
        @"Chaos.Launcher.App.runtimeconfig.json", @"Chaos.Launcher.Core.dll", @"Chaos.Launcher.Platform.dll",
        @"runtimes/osx/native/libAvaloniaNative.dylib", @"runtimes/osx/native/libSkiaSharp.dylib",
        @"runtimes/osx/native/libHarfBuzzSharp.dylib"]) writeFile(version, file, @"fixture");
}

int main(void) {
    @autoreleasepool {
        NSURL *temporary = [NSURL fileURLWithPath:[NSTemporaryDirectory()
            stringByAppendingPathComponent:[@"unora-tests-" stringByAppendingString:NSUUID.UUID.UUIDString]]];
        NSURL *data = [temporary URLByAppendingPathComponent:@"profile with spaces"];
        NSURL *resources = [temporary URLByAppendingPathComponent:@"Resources"];
        NSURL *seeds = [resources URLByAppendingPathComponent:@"Launcher/versions"];
        NSURL *installed = [data URLByAppendingPathComponent:@"Launcher/versions"];
        setenv("UNORA_LAUNCHER_HOME", data.fileSystemRepresentation, 1);
        completeVersion(seeds, @"4.0.11.0");
        writeFile(resources, @"Launcher/run.sh", @"original runner");
        NSError *error = nil;
        NSURL *root = prepareWritableLauncher(resources, @"4.0.11.0", &error);
        check(root != nil && isCompleteVersion([installed URLByAppendingPathComponent:@"4.0.11.0"]),
              @"fresh install in a path containing spaces");
        completeVersion(installed, @"4.0.3.0");
        completeVersion(installed, @"4.0.9.0");
        completeVersion(installed, @".staging-99.0");
        writeFile(installed, @"4.0.99.0/Chaos.Launcher.App.dll", @"partial download");
        check([newestVersionDirectory(installed).lastPathComponent isEqual:@"4.0.11.0"],
              @"numeric ordering skips incomplete and staging updates");
        completeVersion(installed, @"4.0.12.0");
        writeFile(data, @"settings.json", @"saved settings");
        writeFile(data, @"Launcher/run.sh", @"custom runner");
        writeFile(installed, @"4.0.11.0/Chaos.Launcher.Core.dll", @"installed copy");
        root = prepareWritableLauncher(resources, @"4.0.11.0", &error);
        check(root != nil && [newestVersionDirectory(installed).lastPathComponent isEqual:@"4.0.12.0"],
              @"upgrading does not downgrade a newer installed launcher");
        check([[NSString stringWithContentsOfURL:[data URLByAppendingPathComponent:@"settings.json"]
                encoding:NSUTF8StringEncoding error:NULL] isEqual:@"saved settings"] &&
              [[NSString stringWithContentsOfURL:[data URLByAppendingPathComponent:@"Launcher/run.sh"]
                encoding:NSUTF8StringEncoding error:NULL] isEqual:@"custom runner"] &&
              [[NSString stringWithContentsOfURL:[installed URLByAppendingPathComponent:@"4.0.11.0/Chaos.Launcher.Core.dll"]
                encoding:NSUTF8StringEncoding error:NULL] isEqual:@"installed copy"],
              @"existing settings, runner and complete versions are preserved");
        [NSFileManager.defaultManager removeItemAtURL:[installed URLByAppendingPathComponent:
            @"4.0.11.0/Chaos.Launcher.App.deps.json"] error:NULL];
        root = prepareWritableLauncher(resources, @"4.0.11.0", &error);
        check(root != nil && isCompleteVersion([installed URLByAppendingPathComponent:@"4.0.11.0"]),
              @"an interrupted seed install is repaired");
        NSArray *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:
            [data URLByAppendingPathComponent:@"Launcher/recovered"].path error:NULL];
        check(entries.count == 1,
              @"incomplete files are backed up instead of discarded");
        root = prepareWritableLauncher(resources, @"5.0.0.0", &error);
        check(root == nil && error != nil, @"missing bundled version fails without activating a partial copy");
        check(isVersionName(@"4.0.11.0") && !isVersionName(@"4.0.11.0.backup") && !isVersionName(@""),
              @"only numeric version directory names are accepted");
        NSURL *managed = [installed URLByAppendingPathComponent:@"4.0.12.0/Chaos.Launcher.App.dll"];
        const char *restart[] = {"UnoraLauncher", managed.fileSystemRepresentation, "--example"};
        const char *normal[] = {"UnoraLauncher", "--example"};
        check(firstUserArgument(3, restart, managed) == 2 && firstUserArgument(2, normal, managed) == 1,
              @"updater restarts do not pass a duplicate assembly argument");
        [NSFileManager.defaultManager removeItemAtURL:temporary error:NULL];
    }
    return 0;
}
