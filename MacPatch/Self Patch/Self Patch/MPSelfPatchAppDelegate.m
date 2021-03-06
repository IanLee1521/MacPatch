//
//  AppDelegate.m
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

#import "MPSelfPatchAppDelegate.h"
#import "MPWorkerProtocol.h"
#import "PrefsController.h"
#import <SystemConfiguration/SystemConfiguration.h>
#import "EventToSend.h"

static BOOL gDone = false;

@interface FileSizeTransformer : NSValueTransformer

+ (Class)transformedValueClass;
+ (BOOL)allowsReverseTransformation;
- (id)transformedValue:(id)value;

@end

@implementation FileSizeTransformer
+ (Class)transformedValueClass;
{
    return [NSString class];
}

+ (BOOL)allowsReverseTransformation;
{
    return NO;
}
- (id)transformedValue:(id)value;
{
    // Data contains "K" remove it to turn it in to a number value
    double convertedValue = [[value stringByReplacingOccurrencesOfString:@"K" withString:@""] doubleValue];
    // Data is already at k, other wise set bytes to 0
    int multiplyFactor = 1;

    NSArray *tokens = [NSArray arrayWithObjects:@"B",@"KB",@"MB",@"GB",@"TB",nil];

    while (convertedValue > 1024) {
        convertedValue /= 1024;
        multiplyFactor++;
    }

    return [NSString stringWithFormat:@"%4.2f %@",convertedValue, [tokens objectAtIndex:multiplyFactor]];
}
@end

// Private Methods
@interface MPSelfPatchAppDelegate ()

// Helper
- (void)connect;
- (void)connect:(NSError **)err;
- (void)cleanup;
- (void)connectionDown:(NSNotification *)notification;

// Worker Methods
- (int)setCatalogURL;
- (void)unSetCatalogURL;

- (NSArray *)scanForAppleUpdates:(NSError **)err;
- (NSArray *)scanForCustomUpdates:(NSError **)err;
- (int)installAppleSoftwareUpdate:(NSString *)appleUpdate;
- (int)installPKG:(NSString *)aPkgPath target:(NSString *)aTarget env:(NSString *)aEnv;
- (int)runScript:(NSString *)aScript;
- (void)setLogoutHook;
- (BOOL)setPermissionsForFile:(NSString *)aFile;
- (int)createDirAtPathWithIntermediateDirs:(NSString *)path intermediateDirs:(BOOL)withDirs;
- (int)writeDataToFile:(id)data file:(NSString *)aFile;
- (int)writeArrayToFile:(NSArray *)data file:(NSString *)aFile;
- (int)setLoggingState:(BOOL)aState;
- (void)removeStatusFiles;

- (void)generateRebootPatchForDownload:(NSDictionary *)aPatch;

- (void)logoutUserNow;

@end


@implementation MPSelfPatchAppDelegate

@synthesize mpHost;
@synthesize mpHostPort;

@synthesize window;
@synthesize tableView;
@synthesize arrayController;
@synthesize spUpdateButton;
@synthesize spCancelButton;

@synthesize runTaskThread;
@synthesize killTaskThread;
@synthesize defaults;
@synthesize spStatusProgress;


+ (void)initialize
{
	NSMutableDictionary *defaultValues = [NSMutableDictionary dictionary];
	
	[defaultValues setObject:[NSNumber numberWithBool:NO] forKey:@"enableDebugLogging"];
	[defaultValues setObject:[NSNumber numberWithBool:YES] forKey:@"enableScanOnLaunch"];
	
	[[NSUserDefaults standardUserDefaults] registerDefaults:defaultValues];
}

-(void)handleColStateToggle:(NSNotification *)note
{
	NSTableColumn *column = [tableView tableColumnWithIdentifier:@"select"];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([d boolForKey:@"colStateOnLaunch"] == YES) {
		[column setHidden:NO];
	} else {
		[column setHidden:YES];
	}
	[tableView setNeedsDisplay:YES];
}

-(void)handleColSizeToggle:(NSNotification *)note
{
	NSTableColumn *column = [tableView tableColumnWithIdentifier:@"size"];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([d boolForKey:@"colSizeOnLaunch"] == YES) {
		[column setHidden:NO];
	} else {
		[column setHidden:YES];
	}
	[tableView setNeedsDisplay:YES];
}

-(void)handleColBaselineToggle:(NSNotification *)note
{
	NSTableColumn *column = [tableView tableColumnWithIdentifier:@"baseline"];
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if ([d boolForKey:@"colBaselineOnLaunch"] == YES) {
		[column setHidden:NO];
	} else {
		[column setHidden:YES];
	}
	[tableView setNeedsDisplay:YES];
}

-(void)awakeFromNib 
{	
	// This prevents Self Patch from auto relaunching after reboot/logout
	// 10.7 Feature
    if (floor(NSAppKitVersionNumber) > 1038 /* 10.6 */) {
        @try {
            NSApplication *a = [NSApplication sharedApplication];
            [a disableRelaunchOnLogin];
        }
        @catch (NSException * e) {
            // Nothing
        }
    }
	fm = [NSFileManager defaultManager];

    // Get Defaults
    mpDefaults = [[MPDefaults alloc] init];
    [self setDefaults:[mpDefaults defaults]];
    

	// Center the Window
	[window center];
	
	if ([fm fileExistsAtPath:AGENT_PREFS_PLIST] == YES) {	
		if ([fm isReadableFileAtPath:AGENT_PREFS_PLIST] == NO) {
			if ([self setPermissionsForFile:AGENT_PREFS_PLIST] == NO) {
				logit(lcl_vError,@"Error, unable to set permissions needed to read agent plist file.");
			}	
		}
        /* Need a Dialog here with error info */
	}
    
	[patchGroupLabel setStringValue:[defaults objectForKey:@"PatchGroup"]];
	// Make sure the cancel button is not enabled
	[spCancelButton setEnabled:NO];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(receiveAllowInstallRebootPatchesNotification:)
                                                 name:@"AllowInstallRebootPatches"
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AllowInstallRebootPatches" object:self];
}

-(IBAction)windowCloseWillExit:(id)sender
{
	[NSApp terminate:nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification 
{
	// Set up preferences for the app.	
	
	NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
	if (![d objectForKey:@"colBaselineOnLaunch"]) {
		[d setBool:NO forKey:@"colBaselineOnLaunch"];
	}
	if (![d objectForKey:@"colSizeOnLaunch"]) {
		[d setBool:YES forKey:@"colSizeOnLaunch"];
	}
	if (![d objectForKey:@"colStateOnLaunch"]) {
		[d setBool:NO forKey:@"colStateOnLaunch"];
	}
	
	int x = [self setLoggingState:[d boolForKey:@"enableDebugLogging"]];
    
	[self handleColSizeToggle:nil];
	[self handleColStateToggle:nil];
	[self handleColBaselineToggle:nil];
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	[nc addObserver:self selector:@selector(handleColStateToggle:) name:@"MPSelfPatchColStateToggle" object:nil];
	[nc addObserver:self selector:@selector(handleColSizeToggle:) name:@"MPSelfPatchColSizeToggle" object:nil];
	[nc addObserver:self selector:@selector(handleColBaselineToggle:) name:@"MPSelfPatchColBaselineToggle" object:nil];
	
	// Setup logging
	NSString *_logFile = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MPSelfPatch.log"];
	[MPLog setupLogging:_logFile level:lcl_vDebug];
    
	if ([d boolForKey:@"enableDebugLogging"]) {
		// enable logging for all components up to level Debug
		lcl_configure_by_name("*", lcl_vDebug);
		logit(lcl_vInfo,@"***** MPSelfPatch started -- Debug Enabled *****");
	} else {
		// enable logging for all components up to level Info
#ifdef DEBUG
      	lcl_configure_by_name("*", lcl_vDebug);
#else
    	lcl_configure_by_name("*", lcl_vInfo);    
#endif
	
		logit(lcl_vInfo,@"***** MPSelfPatch started *****");
	}

	// If scan on launch is true
	if ([d boolForKey:@"enableScanOnLaunch"]) {
		killTaskThread = NO;
        // Dont run scan if we get a error code other than 0
        if (x == 0) {
            //[spStatusProgress setStyle:NSProgressIndicatorSpinningStyle];
            [spStatusProgress setUsesThreadedAnimation:YES];
            //[spStatusProgress startAnimation:self];
            //[spStatusProgress displayIfNeeded];
            [self scanForPatches:self];
        }
	}
    
	// Center the Window
	[window center];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return YES;
}

-(void)dealloc
{
	[asus release];
    [self cleanup];
	[super dealloc];
}

#pragma mark -
#pragma mark MPWorker
- (void)connect
{
    // Use mach ports for communication, since we're local.
    NSConnection *connection = [NSConnection connectionWithRegisteredName:kMPWorkerPortName host:nil];
	
    [connection setRequestTimeout: 60.0];
    [connection setReplyTimeout: 1800.0]; //30 min to install
	
    @try {
        proxy = [[connection rootProxy] retain];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionDown:) name:NSConnectionDidDieNotification object:connection];
		
        [proxy setProtocolForProxy: @protocol(MPWorkerServer)];
        BOOL successful = [proxy registerClient:self];
        if (!successful) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Error"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue."];
            
            [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [alert runModal];

            [self cleanup];
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Could not connect to MPHelper: %@", e);
        [self cleanup];
    }
}

- (void)connect:(NSError **)err
{
    // Use mach ports for communication, since we're local.
    NSConnection *connection = [NSConnection connectionWithRegisteredName:kMPWorkerPortName host:nil];
	
    [connection setRequestTimeout: 60.0];
    [connection setReplyTimeout: 1800.0]; //30 min to install
	
    @try {
        proxy = [[connection rootProxy] retain];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(connectionDown:) name:NSConnectionDidDieNotification object:connection];
		
        [proxy setProtocolForProxy: @protocol(MPWorkerServer)];
        BOOL successful = [proxy registerClient:self];
        if (!successful) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Error"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue."];
            
            [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [alert runModal];

            NSMutableDictionary *details = [NSMutableDictionary dictionary];
			[details setValue:@"Unable to connect to helper application. Please try logging out and logging back in to resolve the issue." forKey:NSLocalizedDescriptionKey];
            if (err != NULL)  *err = [NSError errorWithDomain:@"world" code:1 userInfo:details];
            [self cleanup];
        }
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Could not connect to MPHelper: %@", e);
        [self cleanup];
    }
}

- (void)cleanup
{
    if (proxy) 
    {
        NSConnection *connection = [proxy connectionForProxy];
        [connection invalidate];
        [proxy release];
        proxy = nil;
    }
	
}

- (void)connectionDown:(NSNotification *)notification 
{
    logit(lcl_vTrace,@"MPWorker connection down");
    [self cleanup];
} 

#pragma mark Client Callbacks
- (void)statusData:(in bycopy NSString *)aData
{
    //[statusTextStatus setStringValue:aData];
}

- (void)installData:(in bycopy NSString *)aData
{
    //[statusTextStatus setStringValue:aData];
}

#pragma mark - Worker Methods

- (int)setCatalogURL
{
    NSError *error = nil;
	int result = 99;
	if (!proxy) {
        [self connect:&error];
        if (error) {
            result = 1001;
        }
        if (!proxy) {
            result = 1002;
            goto done;
        }
    }
	
    @try 
	{
		logit(lcl_vDebug,@"[proxy run setCatalogURL]");
		result = [proxy setCatalogURLViaHelper]; 
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runSetCatalogURLUsingHelper error: %@", e);
		result = 99;
    }
	
done:	
    qltrace(@"Done, setCatalogURL");
	[self cleanup];
	return result;
}

- (void)unSetCatalogURL
{
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try 
	{
		logit(lcl_vDebug,@"[proxy run unSetCatalogURL]");
		[proxy unSetCatalogURLViaHelper]; 
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"unSetCatalogURL error: %@", e);
    }
	
done:	
    qltrace(@"Done, unSetCatalogURL");
	[self cleanup];
	return;
}

- (NSArray *)scanForAppleUpdates:(NSError **)err
{
	NSArray *results = nil;
	NSError *error = nil;
	if (!proxy) {
        [self connect:&error];
        if (error) {
            if (err != NULL) *err = [NSError errorWithDomain:@"scanForAppleUpdates" code:1001 userInfo:nil];
            goto done;
        }
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			goto done;
		} 
    }
	
	@try {
		results = [NSArray arrayWithArray:[proxy scanForAppleUpdatesViaHelper]];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [ASUS Scan] error: %@", e);
    }
	
done:
    qltrace(@"Done, scanForAppleUpdates");
	[self cleanup];
	return results;
}

- (NSArray *)scanForCustomUpdates:(NSError **)err
{
    NSArray *results = nil;
	NSError *error = nil;
	if (!proxy) {
        [self connect:&error];
        if (error) {
            if (err != NULL) *err = [NSError errorWithDomain:@"scanForCustomUpdates" code:1001 userInfo:nil];
            goto done;
        }
        if (!proxy) {
			logit(lcl_vError,@"Unable to connect to helper application. Functionality will be diminished.");
			goto done;
		} 
    }
	
	@try {
		results = [NSArray arrayWithArray:[proxy scanForCustomUpdatesViaHelper]];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [Custom Scan] error: %@", e);
    }
	
done:
    qltrace(@"Done, scanForCustomUpdates");
	[self cleanup];
	return results;
}

- (int)installAppleSoftwareUpdate:(NSString *)appleUpdate
{
	int result = -1;
    [self cleanup];
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try {
		result = [proxy installAppleSoftwareUpdateViaHelper:appleUpdate];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runTaskUsingHelper [ASUS Install] error: %@", e);
		result = 1;
    }
	
done:	
	[self cleanup];
	return result;
}

- (int)installPKG:(NSString *)aPkgPath target:(NSString *)aTarget env:(NSString *)aEnv
{
	int result = 99;
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try {
		logit(lcl_vDebug,@"[proxy installPkgToRootViaHelper:%@ target:%@]",aPkgPath, aTarget);
		result = [proxy installPkgToRootViaHelper:aPkgPath env:aEnv];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runPKGInstallUsingHelper [PKG Install] error: %@", e);
		result = 99;
    }
	
done:	
	[self cleanup];
	return result;
}

- (int)runScript:(NSString *)aScript 
{
	int result = 99;
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try 
	{
		logit(lcl_vDebug,@"[proxy run script:%@]",aScript);
		result = [proxy runScriptViaHelper:aScript];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"runScript error: %@", e);
		result = 99;
    }
	
done:	
	[self cleanup];
	return result;
}

- (void)setLogoutHook
{
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try 
	{
		[proxy setLogoutHookViaHelper];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to set the logout hook, %@", e);
    }
	
done:	
	return;
}

- (BOOL)setPermissionsForFile:(NSString *)aFile
{
	int result = -1;
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try 
	{
		result = [proxy setPermissionsForFileViaHelper:aFile posixPerms:0664UL];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to set the logging level, %@", e);
    }
	
done:	
	[self cleanup];
	if (result == -1 || result == 1) { 
		return NO;
	} else {
		return YES;
	}
	
}

- (int)createDirAtPathWithIntermediateDirs:(NSString *)path intermediateDirs:(BOOL)withDirs
{
    int result = -1;
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try 
	{
		result = [proxy createDirAtPathWithIntermediateDirectoriesViaHelper:path intermediateDirectories:withDirs];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to create dir at path(%@). %@",path, e);
    }
	
done:	
	[self cleanup];
    return result;
}

- (int)writeDataToFile:(id)data file:(NSString *)aFile
{
    int result = -1;
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try 
	{
        result = [proxy writeDataToFileViaHelper:data toFile:aFile];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to write data to file(%@). %@",aFile, e);
    }
	
done:	
	[self cleanup];
    return result;
}

- (int)writeArrayToFile:(NSArray *)data file:(NSString *)aFile
{
    int result = -1;
	if (!proxy) {
        [self connect];
        if (!proxy) goto done;
    }
	
    @try
	{
        result = [proxy writeArrayToFileViaHelper:data toFile:aFile];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to write data to file(%@). %@",aFile, e);
    }
	
done:
	[self cleanup];
    return result;
}

- (int)setLoggingState:(BOOL)aState
{
    int result = 0;
    NSError *error = nil;
	if (!proxy) {
        [self connect:&error];
        if (error) {
            result = 1;
            goto done;
        }
        if (!proxy) {
            result = 1;
            goto done;
        }
    }
	
    @try 
	{
		[proxy setDebugLogging:aState];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to set the logging level, %@", e);
    }
	
done:	
	[self cleanup];
	return result;
}

- (void)removeStatusFiles
{
    NSError *error = nil;
	if (!proxy) {
        [self connect:&error];
        if (error) {
            logit(lcl_vError,@"%@",error.localizedDescription);
            goto done;
        }
        if (!proxy) {
            logit(lcl_vError,@"Could not create proxy object.");
            goto done;
        }
    }

    @try
	{
		[proxy removeStatusFilesViaHelper];
    }
    @catch (NSException *e) {
        logit(lcl_vError,@"Trying to set the logging level, %@", e);
    }

done:
	[self cleanup];
	return;
}

#pragma mark -
#pragma mark SelfPatch
- (void)showSelfPatchWindow:(id)sender
{
	[spScanAndPatchButton setTitle:@"Scan"];
	[spStatusText setStringValue:@""];
	if ([[arrayController arrangedObjects] count] >= 1) {
		[arrayController removeObjects:[arrayController arrangedObjects]];
		[tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
	}
	
	[window	makeKeyAndOrderFront:sender];
	[window center];
	[NSApp arrangeInFront:sender];
	[NSApp activateIgnoringOtherApps:YES];	
}

- (IBAction)scanForPatches:(id)sender
{
	killTaskThread = NO;
	
	if (runTaskThread != nil) {
		[runTaskThread release];
		runTaskThread = nil;
	}
    
    [spStatusProgress setUsesThreadedAnimation:YES];
    [spStatusProgress performSelector:@selector(startAnimation:)
                           withObject:self
                           afterDelay:0.0
                              inModes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
    
	runTaskThread = [[NSThread alloc] initWithTarget:self selector:@selector(runPatchScan) object:nil];
	[runTaskThread start];
	[spCancelButton setEnabled:YES];
}

- (IBAction)installPatches:(id)sender
{
	if (runTaskThread) {
		[runTaskThread release];
		runTaskThread = nil;
	}
    
    [spStatusProgress setUsesThreadedAnimation:YES];
    [spStatusProgress performSelector:@selector(startAnimation:)
                           withObject:self
                           afterDelay:0.0
                              inModes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];

	runTaskThread = [[NSThread alloc] initWithTarget:self selector:@selector(runPatchUpdates) object:nil];
	[runTaskThread start];
	[spCancelButton setEnabled:YES];
}

- (void)runPatchScan
{
    @autoreleasepool
    {
        NSError *appleScanError = nil;
        NSError *customScanError = nil;
        [self setDefaults:[mpDefaults readDefaults]];
        
        [arrayController removeObjects:[arrayController arrangedObjects]];
        [tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
        
        [spUpdateButton setEnabled:NO];
        [spStatusText setStringValue:@"Preparing to scan for patches."];
        [spScanAndPatchButton setEnabled:NO];
        
        // Method Valiables
        NSMutableArray *approvedUpdatesArray = [[NSMutableArray alloc] init];
        NSMutableDictionary *tmpDict;
        NSImage *emptyImage = [NSImage imageNamed:@"empty.tif"];
        NSImage *rebootImage = [NSImage imageNamed:@"RestartReq.tif"];
        NSImage *baselineImage = [NSImage imageNamed:@"Installcomplete.tif"];

        asus = [[MPAsus alloc] init];

        if (killTaskThread == YES) {
            [spStatusText setStringValue:@"Canceling request..."];
            goto done;
        }
        
        // Get Patch Group Patches
        [spStatusText setStringValue:@"Getting approved patch list for client."];
        MPWebServices *mpws;
        mpws = [[[MPWebServices alloc] init] autorelease];
        NSError *wsErr = nil;
        NSDictionary *patchGroupPatches = [mpws getPatchGroupContent:&wsErr];
        if (wsErr) {
            logit(lcl_vError,@"%@",wsErr.localizedDescription);
        }
        if (!patchGroupPatches) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Communications Error"
                                             defaultButton:@"OK"
                                           alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"There was a issue getting the approved patches for the patch group, scan will exit."];
            
            [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [alert runModal];

            logit(lcl_vError,@"There was a issue getting the approved patches for the patch group, scan will exit.");
            goto done;
        }
        NSArray *approvedApplePatches = [patchGroupPatches objectForKey:@"AppleUpdates"];
        NSArray *approvedCustomPatches = [patchGroupPatches objectForKey:@"CustomUpdates"]; 
        
        // Scan for Apple Patches
        int catResult = [self setCatalogURL];
        if (catResult != 0) {
            if (catResult == 1001) {
                goto done;
            }
            logit(lcl_vError,@"There was a issue setting the CatalogURL, Apple updates will not occur.");
        }
        
        if (killTaskThread == YES) {
            [spStatusText setStringValue:@"Canceling request..."];
            goto done;
        }
        
        [spStatusText setStringValue:@"Scanning for Apple software updates..."];
        appleScanError = nil;
        NSArray *applePatchesArray = nil;
        applePatchesArray = [self scanForAppleUpdates:&appleScanError];
        if (appleScanError) {
            goto done;
        }
        
        if (killTaskThread == YES) {
            [spStatusText setStringValue:@"Canceling request..."];
            goto done;
        }
        
        // post patches to web service
        mpws = [[[MPWebServices alloc] init] autorelease];
        wsErr = nil;
        [mpws postClientScanDataWithType:applePatchesArray type:0 error:&wsErr];
        if (wsErr) {
            logit(lcl_vError,@"Scan results posted to webservice returned false.");
            logit(lcl_vError,@"%@",wsErr.localizedDescription);
        } else {
            logit(lcl_vInfo,@"Scan results posted to webservice.");
        }

        if (killTaskThread == YES) {
            [spStatusText setStringValue:@"Canceling request..."];
            goto done;
        }
        
        // Process patches
        if (!applePatchesArray) {
            logit(lcl_vInfo,@"The scan results for ASUS scan were nil.");
        } else {
            // If no items in array, lets bail...
            if ([applePatchesArray count] == 0 ) {
                [spStatusText setStringValue:@"No Apple updates found."];
                sleep(1);
            } else {
                // We have Apple patches, now add them to the array of approved patches
                
                
                // If no items in array, lets bail...
                if ([approvedApplePatches count] == 0 ) {
                    [spStatusText setStringValue:@"No Patch Group patches found."];
                    logit(lcl_vInfo,@"No apple updates found for \"%@\" patch group.",[defaults objectForKey:@"PatchGroup"]);
                } else {
                    // Build Approved Patches
                    [spStatusText setStringValue:@"Building approved patch list..."];
                    
                    for (int i=0; i<[applePatchesArray count]; i++) {
                        for (int x=0;x < [approvedApplePatches count]; x++) {
                            if ([[[approvedApplePatches objectAtIndex:x] objectForKey:@"name"] isEqualTo:[[applePatchesArray objectAtIndex:i] objectForKey:@"patch"]]) {
                                tmpDict = [[NSMutableDictionary alloc] init];
                                [tmpDict setObject:[NSNumber numberWithBool:YES] forKey:@"select"];
                                [tmpDict setObject:[[applePatchesArray objectAtIndex:i] objectForKey:@"size"] forKey:@"size"];
                                [tmpDict setObject:[[applePatchesArray objectAtIndex:i] objectForKey:@"patch"] forKey:@"patch"];
                                [tmpDict setObject:[[applePatchesArray objectAtIndex:i] objectForKey:@"description"] forKey:@"description"];
                                [tmpDict setObject:[[applePatchesArray objectAtIndex:i] objectForKey:@"restart"] forKey:@"restart"];
                                if ([[[[applePatchesArray objectAtIndex:i] objectForKey:@"restart"] uppercaseString] isEqualTo:@"Y"] || [[[[applePatchesArray objectAtIndex:i] objectForKey:@"restart"] uppercaseString] isEqualTo:@"YES"])
                                {
                                    [tmpDict setObject:rebootImage forKey:@"reboot"];
                                } else {
                                    [tmpDict setObject:emptyImage forKey:@"reboot"];
                                }
                                if ([[[applePatchesArray objectAtIndex:i] objectForKey:@"baseline"] isEqualTo:@"1"]) {
                                    [tmpDict setObject:baselineImage forKey:@"baseline"];
                                    break;
                                }
                                
                                [tmpDict setObject:[[applePatchesArray objectAtIndex:i] objectForKey:@"version"] forKey:@"version"];
                                
                                if ([[approvedApplePatches objectAtIndex:x] objectForKey:@"hasCriteria"]) {
                                    
                                    [tmpDict setObject:[[approvedApplePatches objectAtIndex:x] objectForKey:@"hasCriteria"] forKey:@"hasCriteria"];
                                    if ([[[approvedApplePatches objectAtIndex:x] objectForKey:@"hasCriteria"] boolValue] == YES) {
                                        if ([[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_pre"] && [[[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_pre"] count] > 0) {
                                            [tmpDict setObject:[[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_pre"] forKey:@"criteria_pre"];
                                        }
                                        if ([[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_post"] && [[[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_post"] count] > 0) {
                                            [tmpDict setObject:[[approvedApplePatches objectAtIndex:x] objectForKey:@"criteria_post"] forKey:@"criteria_post"];
                                        }
                                    }	
                                }
                                [tmpDict setObject:@"Apple" forKey:@"type"];
                                [tmpDict setObject:[[approvedApplePatches objectAtIndex:i] objectForKey:@"patch_install_weight"] forKey:@"patch_install_weight"];
                                logit(lcl_vDebug,@"Apple Patch Dictionary Added: %@",tmpDict);
                                [approvedUpdatesArray addObject:tmpDict];
                                [tmpDict release];
                                break;
                            }
                        }	
                    }
                }
            }
        }
        if (killTaskThread == YES) {
            [spStatusText setStringValue:@"Canceling request..."];
            goto done;
        }
        
        // Scan for Custom Patches to see what is relevant for the system
        [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                            selector: @selector(scanForNotification:)
                                                                name: @"ScanForNotification"
                                                              object: nil];

        [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                            selector: @selector(scanForNotificationFinished:)
                                                                name: @"ScanForNotificationFinished"
                                                              object: nil];

        [spStatusText setStringValue:@"Scanning for custom updates..."];
        [spStatusText display];
        customScanError = nil;
        NSMutableArray *customPatchesArray = (NSMutableArray *)[self scanForCustomUpdates:&customScanError];
        if (customScanError) {
            goto done;
        }
        
        logit(lcl_vDebug,@"Custom Patches Needed: %@",customPatchesArray);
        logit(lcl_vDebug,@"Approved Custom Patches: %@",approvedCustomPatches);
        
        // Filter List of Patches containing only the approved patches
        NSDictionary *customPatch, *approvedPatch;
        [spStatusText setStringValue:@"Building approved patch list..."];
        [spStatusText display];
        for (int i=0; i<[customPatchesArray count]; i++) {
            customPatch	= [customPatchesArray objectAtIndex:i];
            for (int x=0;x < [approvedCustomPatches count]; x++) {
                approvedPatch	= [approvedCustomPatches objectAtIndex:x];
                if ([[customPatch objectForKey:@"patch_id"] isEqualTo:[approvedPatch objectForKey:@"patch_id"]]) {
                    logit(lcl_vInfo,@"Patch %@ approved for update.",[customPatch objectForKey:@"description"]);
                    tmpDict = [[NSMutableDictionary alloc] init];
                    [tmpDict setObject:[NSNumber numberWithBool:YES] forKey:@"select"];
                    for (id item in [approvedPatch objectForKey:@"patches"]) {
                        if ([[item objectForKey:@"type"] isEqualTo:@"1"]) {
                            [tmpDict setObject:[NSString stringWithFormat:@"%@",[item objectForKey:@"size"]] forKey:@"size"];
                            break;
                        }
                    }
                    for (id item in [approvedPatch objectForKey:@"patches"]) {
                        if ([[item objectForKey:@"baseline"] isEqualTo:@"1"]) {
                            [tmpDict setObject:baselineImage forKey:@"baseline"];
                            break;
                        }
                    }
                    [tmpDict setObject:[customPatch objectForKey:@"patch"] forKey:@"patch"];
                    [tmpDict setObject:[customPatch objectForKey:@"description"] forKey:@"description"];
                    [tmpDict setObject:[customPatch objectForKey:@"restart"] forKey:@"restart"];
                    if ([[[customPatch objectForKey:@"restart"] uppercaseString] isEqualTo:@"TRUE"] || [[[customPatch objectForKey:@"restart"] uppercaseString] isEqualTo:@"YES"])
                    {
                        [tmpDict setObject:rebootImage forKey:@"reboot"];
                    } else {
                        [tmpDict setObject:emptyImage forKey:@"reboot"];
                    }
                    [tmpDict setObject:[customPatch objectForKey:@"version"] forKey:@"version"];
                    [tmpDict setObject:approvedPatch forKey:@"patches"];
                    [tmpDict setObject:[customPatch objectForKey:@"patch_id"] forKey:@"patch_id"];
                    [tmpDict setObject:@"Third" forKey:@"type"];
                    [tmpDict setObject:[customPatch objectForKey:@"bundleID"] forKey:@"bundleID"];
                    [tmpDict setObject:[approvedPatch objectForKey:@"patch_install_weight"] forKey:@"patch_install_weight"];

                    logit(lcl_vDebug,@"Custom Patch Dictionary Added: %@",tmpDict);
                    [approvedUpdatesArray addObject:tmpDict];
                    [tmpDict release];
                    break;
                }
            }	
        }

        NSSortDescriptor *desc = [NSSortDescriptor sortDescriptorWithKey:@"patch_install_weight" ascending:YES];
        [approvedUpdatesArray sortUsingDescriptors:[NSArray arrayWithObject:desc]];

        logit(lcl_vInfo,@"%d patche(s) needed.",(int)[approvedUpdatesArray count]);
        logit(lcl_vDebug,@"Approved patches to install: %@",approvedUpdatesArray);

        // Removing Image, write out array of required patches for Client Status
        NSMutableArray *_requiredPatchesArray = [NSMutableArray new];
        NSMutableDictionary *_dict;
        for (NSDictionary *ePatch in approvedUpdatesArray)
        {
            _dict = [ePatch mutableCopy];
            if ([_dict objectForKey:@"baseline"]) {
                [_dict removeObjectForKey:@"baseline"];
            }
            if ([_dict objectForKey:@"reboot"]) {
                [_dict removeObjectForKey:@"reboot"];
            }
            [_requiredPatchesArray addObject:_dict];
        }

        if (approvedUpdatesArray && [approvedUpdatesArray count] > 0)
        {
            NSString *_approvedPatchesFile = [NSString stringWithFormat:@"%@/Data/.approvedPatches.plist",MP_ROOT_CLIENT];
            
            BOOL isDir;
            BOOL exists = [fm fileExistsAtPath:[_approvedPatchesFile stringByDeletingLastPathComponent] isDirectory:&isDir];
            if (exists) {
                /* file exists */
                if (!isDir) {
                    /* file is a directory */
                    logit(lcl_vWarning,@"Unable to create file %@. \"Data\" directory already exists but is not a directory.",_approvedPatchesFile);
                }
            } else {
                [self createDirAtPathWithIntermediateDirs:[_approvedPatchesFile stringByDeletingLastPathComponent] intermediateDirs:YES];
            }
            
            [self writeArrayToFile:(NSArray *)approvedUpdatesArray file:[NSString stringWithFormat:@"%@/Data/.approvedPatches.plist",MP_ROOT_CLIENT]];
            [self writeArrayToFile:(NSArray *)_requiredPatchesArray file:PATCHES_NEEDED_PLIST];
            
            [arrayController removeObjects:[arrayController arrangedObjects]];
            [arrayController addObjects:approvedUpdatesArray];	
            [tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
        } else {
            NSError *rmErr;
            NSString *approvedPatchesFile = [NSString stringWithFormat:@"%@/Data/.approvedPatches.plist",MP_ROOT_CLIENT];
            if ([fm fileExistsAtPath:approvedPatchesFile])
            {
                if (![fm isDeletableFileAtPath:approvedPatchesFile]) {
                    logit(lcl_vDebug,@"Unable to remove file (%@) due to permissions.",approvedPatchesFile);
                } else {
                    rmErr = nil;
                    logit(lcl_vInfo,@"Removing file %@. No patches found.",[NSString stringWithFormat:@"%@/Data/.approvedPatches.plist",MP_ROOT_CLIENT]);
                    [fm removeItemAtPath:[NSString stringWithFormat:@"%@/Data/.approvedPatches.plist",MP_ROOT_CLIENT] error:&rmErr];
                    if (rmErr) {
                        qlerror(@"%@",rmErr.localizedDescription);
                    }
                }
            }
            if ([fm fileExistsAtPath:PATCHES_NEEDED_PLIST]) {
                logit(lcl_vInfo,@"Removing file %@. No patches found.",PATCHES_NEEDED_PLIST);
                [self removeStatusFiles];
            }
        }
        
    done:

        [spStatusText setStringValue:@"Scan Completed."];
        [spStatusText display];

        [spStatusProgress stopAnimation:nil];
        if  ([approvedUpdatesArray count] <= 0) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Patch Scan Complete"
                                             defaultButton:@"OK" alternateButton:nil
                                               otherButton:nil
                                 informativeTextWithFormat:@"There are no patches needed at this time."];
            
            [[NSRunningApplication currentApplication] activateWithOptions:NSApplicationActivateIgnoringOtherApps];
            [alert runModal];
        } else {
            logit(lcl_vInfo,@"Patches found %d",(int)[[arrayController arrangedObjects] count]);
            [spStatusText setStringValue:[NSString stringWithFormat:@"%d patches needed.",(int)[[arrayController arrangedObjects] count]]];
            [spStatusText display];
            [spUpdateButton setEnabled:YES];
        }
        
        [spScanAndPatchButton setEnabled:YES];
        [spCancelButton setEnabled:NO];
        
        [approvedUpdatesArray release];
        [asus release];
    }
}

- (void)runPatchUpdates
{

    @autoreleasepool
    {
        [spScanAndPatchButton setEnabled:NO];
        [spUpdateButton setEnabled:NO];
        
        [spStatusText setStringValue:@"Begin patching process."];
        [spStatusText display];
        
        if ([self setCatalogURL] != 0) {
            logit(lcl_vError,@"There was a issue setting the CatalogURL, Apple updates will not occur.");
        }

        MPAsus              *mpAsus = [[MPAsus alloc] init];
        NSPredicate         *selectedPatchesPredicate = [NSPredicate predicateWithFormat:@"select == 1"];
        NSMutableArray		*patchesToInstallArray    = [NSMutableArray arrayWithArray:[[arrayController arrangedObjects] filteredArrayUsingPredicate:selectedPatchesPredicate]];
        
        // NSMutableArray      *rebootPatchesToDownload  = [[NSMutableArray alloc] init];
        NSDictionary		*patch;
        NSDictionary		*currPatchToInstallDict;
        NSArray				*patchPatchesArray;
        NSString			*infoText;
        NSString			*downloadURL;
        NSError				*err;
        int i;
        int installResult = 1;
        int	launchRebootWindow = 0;
        
        for (i = 0; i < [patchesToInstallArray count]; i++) {
            // Create/Get Dictionary of Patch to install  
            patch = nil;
            patch = [NSDictionary dictionaryWithDictionary:[patchesToInstallArray objectAtIndex:i]];
            logit(lcl_vDebug,@"Checking to see if patch %@ needs a reboot; \"%@\"",[patch objectForKey:@"patch"],[patch objectForKey:@"restart"]);
            
            // Check if patch needs a reboot
            if (([[[patch objectForKey:@"restart"] uppercaseString] isEqualTo:@"N"] || [[[patch objectForKey:@"restart"] uppercaseString] isEqualTo:@"NO"] || [[[patch objectForKey:@"restart"] uppercaseString] isEqualTo:@"FALSE"]) || [[NSUserDefaults standardUserDefaults] boolForKey:@"allowRebootPatchInstalls"] == YES)
            {
                logit(lcl_vInfo,@"Allow Install of Reboot Patches is %@",[[NSUserDefaults standardUserDefaults] boolForKey:@"allowRebootPatchInstalls"] ? @"ON":@"OFF");
                logit(lcl_vInfo,@"Preparing to install %@(%@)",[patch objectForKey:@"patch"],[patch objectForKey:@"version"]);
                logit(lcl_vDebug,@"Patch to process: %@",patch);
                
                /* Disabled for a min
                 if ([self checkPatchPreAndPostForRebootRequired:patchPatchesArray]) {
                 logit(lcl_vInfo,@"One or more of the pre & post installs requires a reboot, this patch will be installed on logout.");
                 continue;
                 }
                 */
                
                // Now proceed to the download and install			
                installResult = -1;
                
                if ([[patch objectForKey:@"type"] isEqualTo:@"Third"]) {
                    NSString *infoText = [NSString stringWithFormat:@"Starting install for %@",[patch objectForKey:@"patch"]];
                    [spStatusText setStringValue:infoText];
                    [spStatusText display];
                    
                    // Get all of the patches, main and subs
                    // This is messed up, not sure why I have an array right within an array, needs to be fixed ...later :-)
                    patchPatchesArray = [NSArray arrayWithArray:[[patch objectForKey:@"patches"] objectForKey:@"patches"]];
                    logit(lcl_vDebug,@"Current patch has total patches associated with it %d", (int)([patchPatchesArray count]-1));
                    
                    NSString *dlPatchLoc; //Download location Path
                    int patchIndex = 0;
                    for (patchIndex=0;patchIndex < [patchPatchesArray count];patchIndex++) {
                        
                        // Make sure we only process the dictionaries in the NSArray
                        if ([[patchPatchesArray objectAtIndex:patchIndex] isKindOfClass:[NSDictionary class]]) {
                            currPatchToInstallDict = [NSDictionary dictionaryWithDictionary:[patchPatchesArray objectAtIndex:patchIndex]];
                        } else {
                            logit(lcl_vInfo,@"Object found was not of dictionary type; could be a problem. %@",[patchPatchesArray objectAtIndex:patchIndex]);
                            continue;
                        }
                        
                        // Update table view to show whats installing
                        [self updateTableAndArrayControllerWithPatch:patch status:0];
                        
                        // We have a currPatchToInstallDict to work with
                        logit(lcl_vInfo,@"Start install for patch %@ from %@",[currPatchToInstallDict objectForKey:@"url"],[patch objectForKey:@"patch"]);
                        
                        // First we need to download the update
                        @try
                        {
                            logit(lcl_vInfo,@"Start download for patch from %@",[currPatchToInstallDict objectForKey:@"url"]);
                            [spStatusText setStringValue:[NSString stringWithFormat:@"Downloading %@",[[currPatchToInstallDict objectForKey:@"url"] lastPathComponent]]];
                            [spStatusText display];
                            //Pre Proxy Config
                            //downloadURL = [NSString stringWithFormat:@"/mp-content%@",[[currPatchToInstallDict objectForKey:@"url"] urlEncode]];
                            downloadURL = [NSString stringWithFormat:@"/mp-content%@",[currPatchToInstallDict objectForKey:@"url"]];
                            logit(lcl_vInfo,@"Download patch from: %@",downloadURL);
                            err = nil;
                            dlPatchLoc = [mpAsus downloadUpdate:downloadURL error:&err];
                            if (err) {
                                logit(lcl_vError,@"Error downloading a patch, skipping %@. Err Message: %@",[patch objectForKey:@"patch"],[err localizedDescription]);
                                [spStatusText setStringValue:[NSString stringWithFormat:@"Error downloading a patch, skipping %@.",[patch objectForKey:@"patch"]]];
                                [spStatusText display];
                                
                                [self updateTableAndArrayControllerWithPatch:patch status:2];
                                break;
                            }
                            [spStatusText setStringValue:[NSString stringWithFormat:@"Patch download completed."]];
                            [spStatusText display];
                            logit(lcl_vInfo,@"File downloaded to %@",dlPatchLoc);
                        }
                        @catch (NSException *e) {
                            logit(lcl_vError,@"%@", e);
                            [self updateTableAndArrayControllerWithPatch:patch status:2];
                            break;
                        }
                        
                        // *****************************
                        // Validate hash, before install
                        [spStatusText setStringValue:[NSString stringWithFormat:@"Validating downloaded patch."]];
                        [spStatusText display];
                        
                        MPCrypto *mpCrypto = [[MPCrypto alloc] init];
                        NSString *fileHash = [mpCrypto md5HashForFile:dlPatchLoc];
                        [mpCrypto release];
                        
                        logit(lcl_vInfo,@"Downloaded file hash: %@ (%@)",fileHash,[currPatchToInstallDict objectForKey:@"hash"]);
                        if ([[[currPatchToInstallDict objectForKey:@"hash"] uppercaseString] isEqualTo:[fileHash uppercaseString]] == NO) {
                            [spStatusText setStringValue:[NSString stringWithFormat:@"The downloaded file did not pass the file hash validation. No install will occur."]];
                            [spStatusText display];
                            logit(lcl_vError,@"The downloaded file did not pass the file hash validation. No install will occur.");
                            [self updateTableAndArrayControllerWithPatch:patch status:2];
                            continue;
                        }
                        
                        // *****************************
                        // Now we need to unzip
                        [spStatusText setStringValue:[NSString stringWithFormat:@"Uncompressing patch, to begin install."]];
                        [spStatusText display];
                        logit(lcl_vInfo,@"Begin decompression of file, %@",dlPatchLoc);
                        err = nil;
                        [mpAsus unzip:dlPatchLoc error:&err];
                        if (err) {
                            [spStatusText setStringValue:[NSString stringWithFormat:@"Error decompressing a patch, skipping %@.",[patch objectForKey:@"patch"]]];
                            [spStatusText display];
                            logit(lcl_vError,@"Error decompressing a patch, skipping %@. Err Message:%@",[patch objectForKey:@"patch"],[err localizedDescription]);
                            [self updateTableAndArrayControllerWithPatch:patch status:2];
                            break;
                        }
                        [spStatusText setStringValue:[NSString stringWithFormat:@"Patch has been uncompressed."]];
                        [spStatusText display];
                        logit(lcl_vInfo,@"File has been decompressed.");
                        
                        // *****************************
                        // Run PreInstall Script
                        if ([[currPatchToInstallDict objectForKey:@"preinst"] length] > 0 && [[currPatchToInstallDict objectForKey:@"preinst"] isEqualTo:@"NA"] == NO) {
                            [spStatusText setStringValue:[NSString stringWithFormat:@"Begin pre install script."]];
                            [spStatusText display];
                            NSString *preInstScript = [[currPatchToInstallDict objectForKey:@"preinst"] decodeBase64WithNewLinesReturnString:NO];
                            logit(lcl_vDebug,@"preInstScript=%@",preInstScript);
                            if ([self runScript:preInstScript] != 0 ) 
                            {
                                logit(lcl_vError,@"Error (%d) running pre-install script.",(int)installResult);
                                [self updateTableAndArrayControllerWithPatch:patch status:2];
                                break;
                            }
                        }
                        
                        // *****************************
                        // Install the update
                        BOOL hadErr = NO;
                        @try {
                            NSString *pkgPath;
                            NSString *pkgBaseDir = [dlPatchLoc stringByDeletingLastPathComponent];						
                            NSPredicate *pkgPredicate = [NSPredicate predicateWithFormat:@"(SELF like [cd] '*.pkg') OR (SELF like [cd] '*.mpkg')"];
                            NSArray *pkgList = [[fm contentsOfDirectoryAtPath:[dlPatchLoc stringByDeletingLastPathComponent] error:NULL] filteredArrayUsingPredicate:pkgPredicate];
                            installResult = -1;
                            
                            // Install pkg(s)
                            for (int ii = 0; ii < [pkgList count]; ii++) {
                                pkgPath = [NSString stringWithFormat:@"%@/%@",pkgBaseDir,[pkgList objectAtIndex:ii]];
                                [spStatusText setStringValue:[NSString stringWithFormat:@"Installing %@",[pkgPath lastPathComponent]]];
                                [spStatusText display];
                                logit(lcl_vInfo,@"Start install of %@",pkgPath);
                                installResult = [self installPKG:pkgPath target:@"/" env:[currPatchToInstallDict objectForKey:@"env"]];
                                if (installResult != 0) {
                                    [spStatusText setStringValue:[NSString stringWithFormat:@"Error installing patch."]];
                                    [spStatusText display];
                                    logit(lcl_vError,@"Error installing package, error code %d.",installResult);
                                    [self updateTableAndArrayControllerWithPatch:patch status:2];
                                    hadErr = YES;
                                    break;
                                } else {
                                    [spStatusText setStringValue:[NSString stringWithFormat:@"Install was successful."]];
                                    [spStatusText display];
                                    logit(lcl_vInfo,@"%@ was installed successfully.",pkgPath);
                                }
                            } // End Loop
                        }
                        @catch (NSException *e) {
                            [spStatusText setStringValue:[NSString stringWithFormat:@"Error installing patch."]];
                            [spStatusText display];
                            logit(lcl_vError,@"%@", e);
                            logit(lcl_vError,@"Error attempting to install patch, skipping %@. Err Message:%@",[patch objectForKey:@"patch"],[err localizedDescription]);
                            [self updateTableAndArrayControllerWithPatch:patch status:2];
                            break;
                        }
                        if (hadErr) {
                            // We had an error, try the next one.
                            continue;
                        }
                        
                        // *****************************
                        // Run PostInstall Script
                        if ([[currPatchToInstallDict objectForKey:@"postinst"] length] > 0 && [[currPatchToInstallDict objectForKey:@"postinst"] isEqualTo:@"NA"] == NO) {
                            [spStatusText setStringValue:[NSString stringWithFormat:@"Begin post install script."]];
                            [spStatusText display];
                            NSString *postInstScript = [[currPatchToInstallDict objectForKey:@"postinst"] decodeBase64WithNewLinesReturnString:NO];
                            logit(lcl_vDebug,@"postInstScript=%@",postInstScript);
                            if ([self runScript:postInstScript] != 0 ) 
                            {
                                break;
                            }
                        }
                        
                        // *****************************
                        // Instal is complete, post result to web service
                        @try {
                            [self postInstallToWebService:[patch objectForKey:@"patch_id"] type:@"third"];
                        }
                        @catch (NSException *e) {
                            logit(lcl_vError,@"%@", e);
                        }
                        [spStatusText setStringValue:[NSString stringWithFormat:@"Patch install completed."]];
                        [spStatusText display];	 
                        
                        [self updateTableAndArrayControllerWithPatch:patch status:1];
                        
                    } // End patchArray To install
                } else if ([[patch objectForKey:@"type"] isEqualTo:@"Apple"]) {
                    // Process Apple Type Patches
                    
                    infoText = [NSString stringWithFormat:@"Starting install for %@",[patch objectForKey:@"patch"]];
                    logit(lcl_vInfo,@"Apple Dict:%@",patch);
                    logit(lcl_vInfo,@"%@",infoText);
                    
                    [spStatusText setStringValue:infoText];
                    [spStatusText display];
                    
                    // Update the table view to show we are in the install process
                    [self updateTableAndArrayControllerWithPatch:patch status:0];
                    
                    if ([[patch objectForKey:@"hasCriteria"] boolValue] == NO || ![patch objectForKey:@"hasCriteria"]) {
                        
                        installResult = [self installAppleSoftwareUpdate:[patch objectForKey:@"patch"]];
                        
                    } else {
                        logit(lcl_vInfo,@"%@ has install criteria assigned to it.",[patch objectForKey:@"patch"]);
                        
                        NSDictionary *criteriaDictPre, *criteriaDictPost;
                        NSData *scriptData;
                        NSString *scriptText;
                        
                        int i = 0;
                        int s_res;
                        // PreInstall First
                        if ([patch objectForKey:@"criteria_pre"]) {
                            logit(lcl_vInfo,@"Processing pre-install criteria."); 
                            for (i=0;i<[[patch objectForKey:@"criteria_pre"] count];i++)
                            {
                                criteriaDictPre = [[patch objectForKey:@"criteria_pre"] objectAtIndex:i]; 
                                
                                scriptData = [[criteriaDictPre objectForKey:@"data"] decodeBase64WithNewlines:NO];		
                                scriptText = [[NSString alloc] initWithData:scriptData encoding:NSASCIIStringEncoding];
                                
                                s_res = [self runScript:scriptText];
                                if (s_res != 0) {
                                    installResult = 1;
                                    logit(lcl_vError,@"Pre-install script returned false for %@. No install will occur.",[patch objectForKey:@"patch"]); 
                                    [scriptText release];
                                    goto instResult;
                                } else {
                                    logit(lcl_vInfo,@"Pre-install script returned true.");
                                }
                                
                                [scriptText release];
                                criteriaDictPre = nil;
                            }
                        }	
                        // Run the patch install, now that the install has occured.
                        installResult = [self installAppleSoftwareUpdate:[patch objectForKey:@"patch"]];
                        
                        // If Install retuened anything but 0, the dont run post criteria
                        if (installResult != 0) {
                            logit(lcl_vError,@"The install for %@ returned an error.",[patch objectForKey:@"patch"]); 
                            goto instResult;
                        }
                        
                        if ([patch objectForKey:@"criteria_post"]) {
                            logit(lcl_vInfo,@"Processing post-install criteria.");  
                            for (i=0;i<[[patch objectForKey:@"criteria_post"] count];i++)
                            {
                                criteriaDictPost = [[patch objectForKey:@"criteria_post"] objectAtIndex:i];
                                
                                scriptData = [[criteriaDictPost objectForKey:@"data"] decodeBase64WithNewlines:NO];		
                                scriptText = [[NSString alloc] initWithData:scriptData encoding:NSASCIIStringEncoding];
                                
                                s_res = [self runScript:scriptText];
                                if (s_res != 0) {
                                    installResult = 1;
                                    logit(lcl_vError,@"Pre-install script returned false for %@. No install will occur.",[patch objectForKey:@"patch"]); 
                                    [scriptText release];
                                    goto instResult;
                                } else {
                                    logit(lcl_vInfo,@"Post-install script returned true.");	
                                }
                                [scriptText release];
                                criteriaDictPost = nil;
                            }
                        }
                    }
                    
                instResult:				
                    if (installResult != 0) {	
                        [spStatusText setStringValue:[NSString stringWithFormat:@"Error installing update, error code %d.",installResult]];
                        [spStatusText display];	 
                        logit(lcl_vError,@"Error installing update, error code %d.",installResult);
                        [self updateTableAndArrayControllerWithPatch:patch status:2];
                        continue;
                    } else {
                        [spStatusText setStringValue:[NSString stringWithFormat:@"%@ was installed successfully.",[patch objectForKey:@"patch"]]];
                        [spStatusText display];	 
                        logit(lcl_vInfo,@"%@ was installed successfully.",[patch objectForKey:@"patch"]);
                        
                        // Post the results to web service
                        @try {
                            [self postInstallToWebService:[patch objectForKey:@"patch"] type:@"apple"];
                        }
                        @catch (NSException *e) {
                            logit(lcl_vError,@"%@", e);
                        }
                        
                        [spStatusText setStringValue:[NSString stringWithFormat:@"Patch install completed."]];
                        [spStatusText display];	 

                        [self updateTableAndArrayControllerWithPatch:patch status:1];
                    }
                } else {
                    continue;
                }
                
            } else {
                logit(lcl_vInfo,@"%@(%@) requires a reboot, this patch will be installed on logout.",[patch objectForKey:@"patch"],[patch objectForKey:@"version"]);
                //[self generateRebootPatchForDownload:patch];
                
                launchRebootWindow++;
                [self updateTableAndArrayControllerWithPatch:patch status:3];
                continue;
            }
        } //End patchesToInstallArray For Loop
        
        [spStatusText setStringValue:@"Completed."];
        [spScanAndPatchButton setEnabled:YES];
        [spStatusProgress stopAnimation:nil];
        [tableView performSelectorOnMainThread:@selector(reloadData) withObject:nil waitUntilDone:NO];
        
        // Open the Reboot App
        if (launchRebootWindow > 0) {
            [self setLogoutHook];

            if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_9) {
                NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:@"mp.cs.note"];
                [ud setBool:YES forKey:@"patch"];
                [ud setBool:YES forKey:@"reboot"];
                ud = nil;
            }
            [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"kRebootRequiredNotification" object:nil];
            [self openRebootApp];
        }
        
        // Create a file to tell MPStatus to update is patch info...
        [fm createFileAtPath:[CLIENT_PATCH_STATUS_FILE stringByExpandingTildeInPath] 
                                                contents:[@"update" dataUsingEncoding:NSASCIIStringEncoding] 
                                              attributes:nil];
        
        [spCancelButton setEnabled:NO];
    }
}

- (void)openRebootApp
{
    // Show Reboot Modal Window
    NSAlert *rbAlert = [[NSAlert alloc] init];
    [rbAlert setMessageText:@"Install and Restart"];
    [rbAlert setInformativeText:@"MacPatch needs to finish installing updates that require a reboot. Please save your work and exit all applications before continuing.\n\n To finish the installation and restart your computer, click Restart."];
    [rbAlert addButtonWithTitle:@"Restart"];
    [rbAlert addButtonWithTitle:@"Cancel"];
    [rbAlert setIcon:[NSImage imageNamed:@"MPAlert"]];

    dispatch_sync(dispatch_get_main_queue(), ^(){
        int choice = (int)[rbAlert runModal];
        switch (choice)
        {
            case NSAlertFirstButtonReturn: [self logoutUserNow]; break;
        }
        
        NSLog (@"NSAlert runModal: returned %d", choice);
    });
}

- (void)logoutUserNow
{
    
    /* reboot the system using Apple supplied code
     error = SendAppleEventToSystemProcess(kAERestart);
     error = SendAppleEventToSystemProcess(kAELogOut);
     error = SendAppleEventToSystemProcess(kAEReallyLogOut);
     */
    
    OSStatus error = noErr;
#ifdef DEBUG
    error = SendAppleEventToSystemProcess(kAELogOut);
#else
    error = SendAppleEventToSystemProcess(kAEReallyLogOut);
#endif
    
    if (error == noErr) {
        NSLog(@"Computer is going to logout!");
        [NSApp terminate:self];
    } else {
        NSLog(@"Computer wouldn't logout: %d", (int)error);
    }
}

- (void)updateTableAndArrayControllerWithPatch:(NSDictionary *)aPatch status:(int)aStatusImage
{
    NSString *curPatchID;
    if ([[aPatch objectForKey:@"type"] isEqualTo:@"Apple"]) {
        curPatchID = [aPatch objectForKey:@"patch"];
    } else {
        curPatchID = [aPatch objectForKey:@"patch_id"];
    }
    
    [arrayController.arrangedObjects enumerateObjectsUsingBlock:^(id object, NSUInteger index, BOOL *stop)
     {
         NSMutableDictionary *d = object;
         if ([[d objectForKey:@"patch_id"] isEqualTo:curPatchID] || [[d objectForKey:@"patch"] isEqualTo:curPatchID])
         {
             if (aStatusImage == 0) {
                 [d setObject:[NSImage imageNamed:@"NSRemoveTemplate"] forKey:@"statusImage"];
             }
             if (aStatusImage == 1) {
                 [d setObject:[NSImage imageNamed:@"Installcomplete.tif"] forKey:@"statusImage"];
                 [self updateNeededPatchesFile:d];
             }
             if (aStatusImage == 2) {
                 [d setObject:[NSImage imageNamed:@"exclamation.tif"] forKey:@"statusImage"];
             }
             if (aStatusImage == 3) {
                 [d setObject:[NSImage imageNamed:@"LogOutReq.tif"] forKey:@"statusImage"];
             }
             dispatch_async(dispatch_get_main_queue(), ^(void){[tableView display];});
             *stop = YES;
             return;
         }
     }];
}

- (void)updateNeededPatchesFile:(NSDictionary *)aPatch
{
    NSError *error = nil;
    NSMutableArray *patchesNew;
    NSArray *patches;
    if ([fm fileExistsAtPath:PATCHES_NEEDED_PLIST]) {
        patches = [NSArray arrayWithArray:[NSKeyedUnarchiver unarchiveObjectWithFile:PATCHES_NEEDED_PLIST]];
        //[self removeStatusFiles];
        if (error) {
            qlerror(@"%@",error.localizedDescription);
        }
    } else {
        return;
    }

    patchesNew = [[NSMutableArray alloc] init];
    if (patches) {
        for (NSDictionary *p in patches) {
            if ([[p objectForKey:@"patch_id"] isEqualTo:[aPatch objectForKey:@"patch_id"]]) {
                qlinfo(@"Remove patch from array, %@",aPatch);
            } else if ([[p objectForKey:@"patch"] isEqualTo:[aPatch objectForKey:@"patch"]] && [[p objectForKey:@"type"] isEqualTo:@"Apple"]) {
                qlinfo(@"Remove %@ patch from array, %@",[aPatch objectForKey:@"type"], aPatch);
            } else {
                [patchesNew addObject:p];
            }
        }
    }
    if (patchesNew.count >= 1) {
        [self writeArrayToFile:(NSArray *)patchesNew file:PATCHES_NEEDED_PLIST];
    } else {
        [self removeStatusFiles];
    }
}

-(BOOL)checkPatchPreAndPostForRebootRequired:(NSArray *)aDictArray
{	
	BOOL result = NO;
	int x = 0;
	// Look for reboots in other patches attached
	for (x = 0; x < [aDictArray count];x++) {
		if ([[[aDictArray objectAtIndex:x] objectForKey:@"reboot"] isEqualTo:@"Yes"]) {
			result = YES;
			break;
		}
	}
	
	return result;
}

- (void)postInstallToWebService:(NSString *)aPatch type:(NSString *)aType
{
    NSString *statusStr = [NSString stringWithFormat:@"Posting patch install results for %@",aPatch];
    [spStatusText setStringValue:statusStr];
	[spStatusText display];

    BOOL result = NO;
    MPWebServices *mpws = [[[MPWebServices alloc] init] autorelease];
    NSError *wsErr = nil;
    result = [mpws postPatchInstallResultsToWebService:aPatch patchType:aType error:&wsErr];
    if (wsErr) {
        logit(lcl_vError,@"%@",wsErr.localizedDescription);
    } else {
        if (result == TRUE) {
            logit(lcl_vInfo,@"Patch (%@) install result was posted to webservice.",aPatch);
        } else {
            logit(lcl_vError,@"Patch (%@) install result was not posted to webservice.",aPatch);
        }
    }

    return;
}

- (IBAction)showLogInConsole:(id)sender
{
	[[NSWorkspace sharedWorkspace] openFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Logs/MPSelfPatch.log"] withApplication:@"Console"]; 
}

- (IBAction)stopAndCloseSelfPatch:(id)sender
{
	[spStatusText setStringValue:@"Canceling task..."];
	[self setKillTaskThread:YES];
	if (runTaskThread) {
		[runTaskThread cancel];
		[runTaskThread release];
		runTaskThread = nil;
		[spStatusProgress stopAnimation:nil];		
	}
	
	[spCancelButton setEnabled:NO];
	[spScanAndPatchButton setEnabled:YES];
	[self cleanup];
}

- (IBAction)showPrefsPanel:(id)sender
{
	if (!prefsController)
		prefsController = [[PrefsController alloc] init];
	
	[prefsController showWindow:self];
}

- (void)generateRebootPatchForDownload:(NSDictionary *)aPatch
{
    
    if ([[aPatch objectForKey:@"type"] isEqualTo:@"Third"])
    {
        // Setup Reboot Patch Dictionary
        NSMutableDictionary *reboot = [[NSMutableDictionary alloc] init];
        [reboot setObject:aPatch forKey:@"patch"];
        
        // Read & Write Reboot Patches to the .MPAuthPatches.plist
        NSMutableArray *rebootDictArray;
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/tmp/.MPAuthPatches.plist"])
        {
            rebootDictArray = [NSKeyedUnarchiver unarchiveObjectWithFile:@"/private/tmp/.MPAuthPatches.plist"];
        } else {
            rebootDictArray = [[NSMutableArray alloc] init];
        }
        
        // Init MPAsus to download the patch
        MPAsus *mpa = [[MPAsus alloc] init];
        qlinfo(@"Generate Download Object for Reboot Patch (%@)",[aPatch objectForKey:@"patch"]);
        
        NSError *err = nil;
        NSArray *patchPatchesArray = [NSArray arrayWithArray:[[aPatch objectForKey:@"patches"] objectForKey:@"patches"]];
        NSDictionary *currPatchToInstallDict = nil;
        
        for (int pIdx=0;pIdx < [patchPatchesArray count];pIdx++)
        {
            
            // Make sure we only process the dictionaries in the NSArray
            if ([[patchPatchesArray objectAtIndex:pIdx] isKindOfClass:[NSDictionary class]]) {
                currPatchToInstallDict = [NSDictionary dictionaryWithDictionary:[patchPatchesArray objectAtIndex:pIdx]];
                [reboot setObject:currPatchToInstallDict forKey:@"patchToInstall"];
            } else {
                logit(lcl_vInfo,@"Object found was not of dictionary type; could be a problem. %@",[patchPatchesArray objectAtIndex:pIdx]);
                continue;
            }
            
            @try
            {
                qlinfo(@"Downloading %@",[[currPatchToInstallDict objectForKey:@"url"] lastPathComponent]);
                //NSString *downloadURL = [NSString stringWithFormat:@"/mp-content%@",[[currPatchToInstallDict objectForKey:@"url"] urlEncode]];
                NSString *downloadURL = [NSString stringWithFormat:@"/mp-content%@",[currPatchToInstallDict objectForKey:@"url"]];
                [reboot setObject:downloadURL forKey:@"downloadURL"];
                qlinfo(@"Download patch from: %@",downloadURL);
                
                [spStatusText setStringValue:[NSString stringWithFormat:@"Downloading %@ for later install.",[[currPatchToInstallDict objectForKey:@"url"] lastPathComponent]]];
                [spStatusText display];
                
                err = nil;
                NSString *dlPatchLoc = [mpa downloadUpdate:downloadURL error:&err];
                if (err) {
                    logit(lcl_vError,@"Error downloading a patch, skipping %@. Err Message: %@",[aPatch objectForKey:@"patch"],[err localizedDescription]);
                    break;
                }
                [reboot setObject:dlPatchLoc forKey:@"patchLocation"];
                logit(lcl_vInfo,@"Patch download completed.");
                logit(lcl_vInfo,@"File downloaded to %@",dlPatchLoc);
            }
            @catch (NSException *e) {
                logit(lcl_vError,@"%@", e);
                break;
            }
        }
        
        [rebootDictArray addObject:reboot];
        [NSKeyedArchiver archiveRootObject:rebootDictArray toFile:@"/private/tmp/.MPAuthPatches.plist"];
    }
    
}

#pragma mark Notifications

- (void)receiveAllowInstallRebootPatchesNotification:(NSNotification *)notification
{
    if(notification)
    {
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"allowRebootPatchInstalls"] == YES)
        {
            [patchNoteLabel setStringValue:@""];
            [_allowRebootInstallsWarningImage setHidden:NO];
            [_allowRebootInstallsWarningImage display];
            [_allowRebootInstallsWarningLabel setHidden:NO];
            [_allowRebootInstallsWarningLabel display];
        } else {
            [patchNoteLabel setStringValue:@"Note:  Once patching has been started, patches that require a reboot will be installed on logout."];
            [_allowRebootInstallsWarningImage setHidden:YES];
            [_allowRebootInstallsWarningImage display];
            [_allowRebootInstallsWarningLabel setHidden:YES];
            [_allowRebootInstallsWarningLabel display];
        }
    }
}

- (void)scanForNotification:(NSNotification *)notification
{
	if(notification)
	{
        NSDictionary *tmpDict = [notification userInfo];
		[spStatusText setStringValue:[NSString stringWithFormat:@"Scanning for %@",[tmpDict objectForKey:@"pname"]]];
		[spStatusText display];
	}	
}

- (void)scanForNotificationFinished:(NSNotification *)notification
{
    if(notification)
	{
        NSDictionary *tmpDict = [notification userInfo];
		NSNumber *patchesNeeded = [tmpDict objectForKey:@"patchesNeeded"];
        logit(lcl_vTrace,@"Number of patches needed %d",[patchesNeeded intValue]);
	}	
}

- (void)readInstallData:(NSNotification *)notification
{
	if(notification)
	{
		NSDictionary *tmpDict = [notification userInfo];
		if ([tmpDict objectForKey:@"pname"]) {
			[spStatusText setStringValue:[NSString stringWithFormat:@"Scanning for %@",[tmpDict objectForKey:@"pname"]]];
			[spStatusText display];	
		}
		if ([tmpDict objectForKey:@"iData"]) {
			logit(lcl_vDebug,@"readInstallData: %@",[tmpDict objectForKey:@"iData"]);
		}	
	}
}

- (void)installStatusCompleteNotify:(NSNotification *)notification
{
	if(notification)
	{
		NSDictionary *tmpDict = [notification userInfo];
		if ([tmpDict objectForKey:@"patchesNeeded"]) {
			NSNumber *patchesNeeded = [tmpDict objectForKey:@"patchesNeeded"];
			
			[spStatusText setStringValue:[NSString stringWithFormat:@"%d patches needed.",[patchesNeeded intValue]]];
			[spStatusText display];
		}
		gDone = true;
	}	
}
@end
