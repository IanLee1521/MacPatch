//
//  main.m
//  MPLoginAgent
/*
 Copyright (c) 2013, Lawrence Livermore National Security, LLC.
 Produced at the Lawrence Livermore National Laboratory (cf, DISCLAIMER).
 Written by Charles Heizer <heizer1 at llnl.gov>.
 LLNL-CODE-636469 All rights reserved.
 
 This file is part of MacPatch, a program for installing and patching
 software.
 
 MacPatch is free software; you can redistribute it and/or modify it under
 the terms of the GNU General Public License (as published by the Free
 Software Foundation) version 2, dated June 1991.
 
 MacPatch is distributed in the hope that it will be useful, but WITHOUT ANY
 WARRANTY; without even the IMPLIED WARRANTY OF MERCHANTABILITY or FITNESS
 FOR A PARTICULAR PURPOSE. See the terms and conditions of the GNU General Public
 License for more details.
 
 You should have received a copy of the GNU General Public License along
 with MacPatch; if not, write to the Free Software Foundation, Inc.,
 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
 */

#import <Cocoa/Cocoa.h>

static void WaitForWindowServerSession(void)
// This routine waits for the window server to register its per-session
// services in our session.  This code was necessary in various pre-release
// versions of Mac OS X 10.5, but it is not necessary on the final version.
// However, I've left it in, and the option to enable it, to give me the
// flexibility to test this edge case.
{
    do {
        NSDictionary *  sessionDict;
        sessionDict = CFBridgingRelease( CGSessionCopyCurrentDictionary() );
        if (sessionDict != nil) {
            break;
        }
        sleep(1);
    } while (YES);
}

static void InstallHandleSIGTERMFromRunLoop(void)
// This routine installs a SIGTERM handler that's called on the main thread, allowing
// it to then call into Cocoa to quit the app.
{
    static dispatch_once_t   sOnceToken;
    static dispatch_source_t sSignalSource;
    
    dispatch_once(&sOnceToken, ^{
        signal(SIGTERM, SIG_IGN);
        
        sSignalSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        assert(sSignalSource != NULL);
        
        dispatch_source_set_event_handler(sSignalSource, ^{
            assert([NSThread isMainThread]);
            [[NSApplication sharedApplication] terminate:nil];
        });
        
        dispatch_resume(sSignalSource);
    });
}

int main(int argc, char * argv[])
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:@"/private/tmp/.MPAuthRun"]) {
        return 0;
    } else {
        // This way it does not run over and over
        [fm removeFileIfExistsAtPath:@"/private/tmp/.MPAuthRun"];
    }
    
    int             retVal;
    NSTimeInterval  delay;
    
    // Register the default defaults, so to speak.
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
                                                              @"DelayStartup":               @0.0,
                                                              @"WaitForWindowServerSession": @NO,
                                                              @"ForceOrderFront":            @YES,
                                                              @"CleanExit":                  @YES,
                                                              @"Debug":                      @NO,
                                                              }];
    
    // Handle various options startup options.
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"WaitForWindowServerSession"]) {
        WaitForWindowServerSession();
    }
    
    delay = [[NSUserDefaults standardUserDefaults] doubleForKey:@"DelayStartup"];
    if (delay > 0.0) {
        [NSThread sleepForTimeInterval:delay];
    }
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CleanExit"]) {
        //NSLog(@"Installing SIGTERM handler");
        InstallHandleSIGTERMFromRunLoop();
    } else {
        //NSLog(@"Not installing SIGTERM handler");
    }

    retVal = NSApplicationMain(argc, (const char **) argv);
    return retVal;
}
