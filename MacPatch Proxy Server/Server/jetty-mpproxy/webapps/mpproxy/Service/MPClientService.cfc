<!--- **************************************************************************************** --->
<!---
        MPClientService Proxy File
        Database type is MySQL
        MacPatch Version 2.2.x
--->
<!---   Notes:
--->
<!--- **************************************************************************************** --->
<cfcomponent>
    <cfset this.logFile = "MPClientService">
    <cfset this.wsURL   = "https://#server.mp.settings.proxyserver.primaryServer#:#server.mp.settings.proxyserver.primaryServerPort#/Service/MPClientService.cfc">
	
    <cffunction name="init" returntype="MPClientService" output="no">
		<cfreturn this>
	</cffunction>

<!--- **************************************************************************************** --->
<!--- Begin Client WebServices Methods --->

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Simple Test To See if WebService is alive and working
    --->
    <cffunction name="WSLTest" access="remote" returnType="struct" returnFormat="json" output="false">
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "0" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = #CreateODBCDateTime(now())# />
        
        <cfreturn response>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: 
    --->
    <cffunction name="client_checkin_base" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="data">
        <cfargument name="type">
        
        <cfset var result = "" />
        <cfset var _methodName = "client_checkin_base"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="data" value="#arguments.data#">
                <cfhttpparam type="formfield" name="type" value="#arguments.type#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: 
    --->
    <cffunction name="client_checkin_plist" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="data">
        <cfargument name="type">
    
        <cfset var result = "" />
        <cfset var _methodName = "client_checkin_plist"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="data" value="#arguments.data#">
                <cfhttpparam type="formfield" name="type" value="#arguments.type#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Name: GetAgentUpdaterUpdates
        Description: Returns The Agent Updater update info
    --->
    <cffunction name="GetAgentUpdaterUpdates" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID">
        <cfargument name="agentUp2DateVer">
        
        <cfset var result = "" />
        <cfset var _methodName = "GetAgentUpdaterUpdates"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

		<!--- Disabledright now --->
		<cfreturn #response#>
        
        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="agentUp2DateVer" value="#arguments.agentUp2DateVer#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns The Agent Updater info
    --->
    <cffunction name="GetAgentUpdates" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="no">
        <cfargument name="agentVersion" default="0">
        <cfargument name="agentBuild" default="0">
        
        <cfset var result = "" />
        <cfset var _methodName = "GetAgentUpdates"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

		<!--- Disabledright now --->
		<cfreturn #response#>
        
        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="agentVersion" value="#arguments.agentVersion#">
                <cfhttpparam type="formfield" name="agentBuild" value="#arguments.agentBuild#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns The Current AVDefs date
    --->
    <cffunction name="GetAVDefsDate"  access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="false" default="0" />
        <cfargument name="avAgent" required="true">
        <cfargument name="theArch" required="false" default="x86">
        
        <cfset var result = "" />
        <cfset var _methodName = "GetAVDefsDate"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="avAgent" value="#arguments.avAgent#">
                <cfhttpparam type="formfield" name="theArch" value="#arguments.theArch#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns The Current AVDefs file path for install 
    --->
    <cffunction name="GetAVDefsFile" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="false" default="0" />
        <cfargument name="avAgent" required="true">
        <cfargument name="theArch" required="false" default="x86">
        
        <cfset var result = "" />
        <cfset var _methodName = "GetAVDefsFile"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="avAgent" value="#arguments.avAgent#">
                <cfhttpparam type="formfield" name="theArch" value="#arguments.theArch#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction> 

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns the JSON formatted patch group data for a requested group
    --->
    <cffunction name="GetIsHashValidForPatchGroup" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="no" default="0" type="string">
        <cfargument name="PatchGroup" required="yes">
        <cfargument name="Hash" required="yes" type="string">
    
        <cfset var result = "" />
        <cfset var _methodName = "GetIsHashValidForPatchGroup"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="PatchGroup" value="#arguments.PatchGroup#">
                <cfhttpparam type="formfield" name="Hash" value="#arguments.Hash#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>
    
    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns the JSON formatted patch group data for a requested group
    --->
    <cffunction name="GetPatchGroupPatches" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="no" default="0" type="string">
        <cfargument name="PatchGroup" required="yes">
        <cfargument name="DataType" required="no" default="JSON" type="string">
    
        <cfset var result = "" />
        <cfset var _methodName = "GetPatchGroupPatches"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="PatchGroup" value="#arguments.PatchGroup#">
                <cfhttpparam type="formfield" name="DataType" value="#arguments.DataType#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns the custom patch scan data
    --->
    <cffunction name="GetScanList" access="remote" returnType="any" returnFormat="plain" output="false">
        <cfargument name="clientID" required="no" default="0" type="string">
        <cfargument name="state" required="no" default="all" type="string">
        <cfargument name="active" required="no" default="1" type="string">
        
        <cfset var result = "" />
        <cfset var _methodName = "GetScanList"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="state" value="#arguments.state#">
                <cfhttpparam type="formfield" name="active" value="#arguments.active#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <!---<cfset result = "#deserializejson(cfhttp.fileContent)#">--->
	        <cfset result = "#cfhttp.fileContent#">
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Add client AV data for SEP or SAV types
    --->
    <cffunction name="PostClientAVData" access="remote" returnType="struct" returnformat="json" output="false">
        <cfargument name="clientID" required="false" default="0" />
        <cfargument name="avAgent" required="true">
        <cfargument name="jsonData" required="true">
        
        <cfset var result = "" />
        <cfset var _methodName = "PostClientAVData"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="avAgent" value="#arguments.avAgent#">
                <cfhttpparam type="formfield" name="jsonData" value="#arguments.jsonData#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Post DataMgr XML and write it out for inventory app to pick it up
    --->
    <cffunction name="PostDataMgrXML" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID">
        <cfargument name="encodedXML">
        
        <cfset var result = "" />
        <cfset var _methodName = "PostDataMgrXML"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="encodedXML" value="#arguments.encodedXML#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Post Client Patch Install Results
    --->
    <cffunction name="PostInstalledPatch" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="false" default="0" />
        <cfargument name="clientKey" required="false" default="0" />
        <cfargument name="patch" required="false" default="0" />
        <cfargument name="patchType" required="false" default="0" />

        <cfset var result = "" />
        <cfset var _methodName = "PostInstalledPatch"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="clientKey" value="#arguments.clientKey#">
                <cfhttpparam type="formfield" name="patch" value="#arguments.patch#">
                <cfhttpparam type="formfield" name="patchType" value="#arguments.patchType#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns Apple Software Update Catalogs based on OSMinior version
    --->
    <cffunction name="GetAsusCatalogs" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="false" default="0" />
        <cfargument name="osminor" required="yes" type="string">
        <cfargument name="clientKey" required="false" default="0" />

        <cfset var result = "" />
        <cfset var _methodName = "GetAsusCatalogs"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="osminor" value="#arguments.osminor#">
                <cfhttpparam type="formfield" name="clientKey" value="#arguments.clientKey#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns the number of patches needed by a client
    --->
    <cffunction name="GetClientPatchStatusCount" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="false" default="0" />
        <cfargument name="clientKey" required="false" default="0" />

        <cfset var result = "" />
        <cfset var _methodName = "GetClientPatchStatusCount"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="clientKey" value="#arguments.clientKey#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns the last datetime a client checked in
    --->
    <cffunction name="GetLastCheckIn" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="false" default="0" />
        <cfargument name="clientKey" required="false" default="0" />

        <cfset var result = "" />
        <cfset var _methodName = "GetLastCheckIn"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="clientKey" value="#arguments.clientKey#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns json data of SW tasks for a SW group
        Note: This function needs to be updated so that the entire JSON result is not 
        stored in the DB just the data.
    --->
    <cffunction name="GetSoftwareTasksForGroup" access="remote" returnType="any" returnFormat="plain" output="false">
        <cfargument name="GroupName">

        <cfset var result = "" />
        <cfset var _methodName = "GetSoftwareTasksForGroup"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="GroupName" value="#arguments.GroupName#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

        <cfreturn SerializeJson(result)>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Returns a list of software group names and description
    --->
    <cffunction name="GetSWDistGroups" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="clientID" required="false" default="0" />
        <cfargument name="state" required="false" default="1" />
        
        <cfset var result = "" />
        <cfset var _methodName = "GetSWDistGroups"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="state" value="#arguments.state#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>

    <!--- 
        Remote API
        Type: Public/Remote
        Description: Function to post client software install results
    --->
    <cffunction name="PostSoftwareInstallResults" access="remote" returnType="struct" returnFormat="json" output="false">
        <cfargument name="ClientID">
        <cfargument name="SWTaskID">
        <cfargument name="SWDistID">
        <cfargument name="ResultNo">
        <cfargument name="ResultString">
        <cfargument name="Action">
        
        <cfset var result = "" />
        <cfset var _methodName = "PostSoftwareInstallResults"/>
    
        <cfset response = {} />
        <cfset response[ "errorno" ] = "1" />
        <cfset response[ "errormsg" ] = "" />
        <cfset response[ "result" ] = "" />

        <cftry>
           	<cfhttp url="#this.wsURL#" method="POST" resolveurl="NO">
                <cfhttpparam type="header" name="charset" value="utf-8">
                <cfhttpparam type="formfield" name="method" value="#_methodName#">
                <cfhttpparam type="formfield" name="clientID" value="#arguments.clientID#">
                <cfhttpparam type="formfield" name="SWTaskID" value="#arguments.SWTaskID#">
                <cfhttpparam type="formfield" name="SWDistID" value="#arguments.SWDistID#">
                <cfhttpparam type="formfield" name="ResultNo" value="#arguments.ResultNo#">
                <cfhttpparam type="formfield" name="ResultString" value="#arguments.ResultString#">
                <cfhttpparam type="formfield" name="Action" value="#arguments.Action#">
            </cfhttp>
               
			<cfif cfhttp.responseheader.STATUS_CODE NEQ "200">
			   <cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#">
			   <cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
			   <cfset result = response>
			</cfif>
	        <cfset result = "#deserializejson(cfhttp.fileContent)#">	
			
			<cfcatch>
				<cflog type="error" file="#this.logFile#" text="#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #cfcatch.message# #cfcatch.detail#">
				<cfset response[ "errorMsg" ] = "#CreateODBCDateTime(now())# -- [#_methodName#][#CGI.REMOTE_HOST#]: #XMLParse(cfhttp.FileContent)#" />
				<cfset result = response>
			</cfcatch>
		</cftry>

		<cfreturn #result#>
    </cffunction>
</cfcomponent>
