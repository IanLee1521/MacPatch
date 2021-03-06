//
//  MacPatch.h
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

#define MASTER_PASSWORD "PASSWORD" // This is not used any where

#import <Cocoa/Cocoa.h>
#import "Constants.h"
// Logging
#import "lcl.h"
#import "MPLog.h"
// Uitlities & Networking
#import "MPNetworkUtils.h"
#import "MPDefaults.h"
#import "MPDiskUtil.h"
#import "MPSystemInfo.h"
#import "MPDate.h"
#import "MPClientCheckInData.h"
#import "MPNSTask.h"

// New Networking
#import "MPNetConfig.h"
#import "MPNetRequest.h"
#import "MPNetServer.h"
#import "MPJsonResult.h"
#import "Reachability.h"
#import "MPServerList.h"
#import "MPNetReach.h"
#import "MPSUServerList.h"

// Patching & Scanning
#import "MPAsus.h"
#import "MPPatchScan.h"
#import "MPBundle.h"
#import "MPFileCheck.h"
#import "MPOSCheck.h"
#import "MPScript.h"
#import "MPASUSCatalogs.h"
#import "MPInstaller.h"
#import "MPApplePatch.h"
#import "MPCustomPatch.h"

// Software Distribution
#import "MPSWTasks.h"
#import "MPSWInstaller.h"

// WebServices
#import "MPDataMgr.h"
#import "MPWebServices.h"
#import "MPFailedRequests.h"

// Crypto
#import "MPCrypto.h"
#import "MPCodeSign.h"
#import "RSACrypto.h"
#import "MPKeychain.h"

// Helpers
#import "NSString-Base64Extensions.h"
#import "NSData-Base64Extensions.h"
#import "NSString+Helper.h"
#import "NSString+Hash.h"
#import "NSFileManager+Helper.h"
#import "NSFileManager+DirectoryLocations.h"
#import "NSDictionary+Helper.h"
#import "NSMutableDictionary+Helper.h"
#import "NSDate+Helper.h"
#import "NSData+Base64.h"

// Inventory Plugin
//#import "InventoryPlugin.h"
