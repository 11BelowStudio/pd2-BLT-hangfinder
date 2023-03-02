-- pls no halting problem :)
if not HangFinder then 

	_G.HangFinder = {
		load_timeout_duration = 10, --after 10s of attempting to load any single resource, log the error
		hang_resolution_enabled = true, --if true, cancels loading any resource that times out (after above duration)
		loading_asset_queue = {},
		known_beardlib_assets = {},
		known_mod_overrides = {},
		known_asset_types = { --i missed a few but these are probably the main ones
			"animation",
			"bnk",
			"stream",
			"bmfc",
			"font",
			"merged_font",
			"gui",
			"model",
			"scene",
			"effect",
			"texture",
			"material_config",
			"movie",
			"unit",
			"obj",
			"physic_effect",
			"achievement",
			"credits",
			"timeline",
			"movie_theater",
			"neural_net",
			"action_message",
			"dialog",
			"cameras",
			"decals",
			"shaders"
		},
		_known_asset_types = {}
	}
	
	function HangFinder.new_clbk(clbk,extra_clbk)
		--made for (...) visibility reasons
		return function(complete,resource_type,resource_name,...)
			
			--do extra stuff
			if extra_clbk then
				extra_clbk(complete,resource_type,resource_name,...)
			end
			
			--return unchanged clbk
			if clbk then
				return clbk(complete,resource_type,resource_name,...)
			end
		end
	end
	
	function HangFinder.force_unload(resource_type,resource_name,package_name)
		managers.dyn_resource:unload(resource_type,resource_name,package_name,false)
	end
	
	function HangFinder.recursive_search_directory(path,folder_cb,file_cb)
		local path_util = BeardLib.Utils.Path
		local file_util = _G.FileIO
		local folders_in_path = file_util:GetFolders(path)
		for	_,folder in pairs(folders_in_path) do
			local subpath = path .. folder .. "/"
			folder_cb(subpath,folder_cb,file_cb)
		end
		local files_in_path = file_util:GetFiles(path)
		for	_,filename in pairs(files_in_path) do
			local subpath = path .. filename
			file_cb(subpath)
		end
	end

	function HangFinder:add_all_mod_overrides_names()
		if BeardLib then
			local path_util = BeardLib.Utils.Path
			local file_util = _G.FileIO
			
			local function clbk_register_file(path)
				self.known_mod_overrides[Idstring(path)] = path
			end
			
			local mod_overrides_path = "/assets/mod_overrides/"
			if file_util:DirectoryExists(Application:nice_path(mod_overrides_path,true)) then
				self.recursive_search_directory(mod_overrides_path,self.recursive_search_directory,clbk_register_file)
			end
			
		end
	end

	function HangFinder:find_asset_name(path_ids,ext_ids)
		if not path_ids then return end
		
		if self.known_mod_overrides[path_ids] then 
			return self.known_mod_overrides[path_ids]
		end
		
		if ext_ids and BeardLib and Global.fm.added_files then
			local ext_key = ext_ids:key()
			local path_key = path_ids:key()
			local ext_added = Global.fm.added_files[ext_key]
			if ext_added then 
				for _path_key,data in pairs(ext_added) do 
					if _path_key == path_key then
						--if data.path == path_ids then
						return tostring(data.file)
					end
				end
			end
		end
		
	end

	for _,type_name in pairs(HangFinder.known_asset_types) do 
		HangFinder._known_asset_types[Idstring(type_name)] = type_name
	end
	function HangFinder:find_asset_type(_type)
		return _type and self._known_asset_types[_type] or nil
	end

	function HangFinder:register_loading_asset(resource_type,resource_name,package_name)
		self.loading_asset_queue[resource_name] = {
			_name = resource_name,
			_type = resource_type,
			_package = package_name
		}
		local load_info = "[NONE]"
		if resource_name then
			local name = self:find_asset_name(resource_name,resource_type) or tostring(resource_name)
			local _type = self:find_asset_type(resource_type) or tostring(resource_type)
	--		local name = hashlist_for_the_poor[resource_name:key()]
	--		local _type = hashlist_for_the_poor[resource_type:key()]
			load_info = string.format("%s [%s]",name or "nil",_type or "nil")
		end
		
		self:logLoadStart(load_info)
		
		DelayedCalls:Add("HangFinder_load_expired_" .. tostring(resource_name),self.load_timeout_duration,function()
			local msg = " Took too long to load asset: " .. load_info
			if self.hang_resolution_enabled then
				msg = msg .. " | Force unloading asset..."
				self:logLoadFail(msg)
				--log message before attempting unload
				self.force_unload(resource_type,resource_name,package_name)
			else
				self:logLoadFail(msg)
			end
		end)
		--add timeout delayedcall
	end

	function HangFinder:unregister_loading_asset(complete,resource_type,resource_name)
		if resource_name then
			DelayedCalls:Remove("HangFinder_load_expired_" .. tostring(resource_name))
			self.loading_asset_queue[resource_name] = nil
			local name = self:find_asset_name(resource_name,resource_type) or tostring(resource_name)
			local _type = self:find_asset_type(resource_type) or tostring(resource_type)
	--		local name = hashlist_for_the_poor[resource_name:key()]
	--		local _type = hashlist_for_the_poor[resource_type:key()]
			load_info = string.format("%s [%s]",name or "nil",_type or "nil")
			self:logLoadEnd(load_info)
		end
	end
	
	
	
	
	function HangFinder:log(message)
		log("[HangFinder] " .. message)
	end
	
	function HangFinder:logLoadStart(thingThatIsLoading)
		self:log("Started loading " .. thingThatIsLoading .. "!")
	end
	
	function HangFinder:logLoadFail(thingThatDidntLoad)
		self:log("Failed to load " .. thingThatDidntLoad)
	end
	
	function HangFinder:logLoadEnd(thingThatLoaded)
		self:log("Finished loading " .. thingThatLoaded .. "!")
	end
	
	HangFinder:log("HangFinder ready!")

end

HangFinder:add_all_mod_overrides_names()
HangFinder:log("added all mod_overrides!")

local orig_load = DynamicResourceManager.load
function DynamicResourceManager:load(resource_type,resource_name,package_name,complete_clbk,...)
	--register asset in the list
	--successfully loaded/unloaded assets are removed from the list
	--assets that fail to load are not removed
	--after x seconds, log timeout error failed loading whatever asset
	HangFinder:register_loading_asset(resource_type,resource_name,package_name)
	
	local new_complete_clbk = HangFinder.new_clbk(complete_clbk,function()
		HangFinder:unregister_loading_asset(true,resource_type,resource_name)
	end) --insert a new callback to register/unregister assets being loaded
	return orig_load(self,resource_type,resource_name,package_name,new_complete_clbk,...)
end

do return end

--[[

-- disabled hoppip's idstring workaround bc it was too spicy for pd2 to handle
-- hoppip's very epic hashlist workaround
local hashlist_for_the_poor = {}

local idsfunc = _G.Idstring
function Idstring(str,...)
	local ids = idsfunc(tostring(str),...)
	
	hashlist_for_the_poor[ids:key()] = str

	return idsfunc(str,...)
end


-- printout whenever starting to load an asset
Hooks:PreHook(
	DynamicResourceManager,
	"load",
	"hangfinder_DRM_load",
	function(self, resource_type, resource_name, package_name, complete_clbk)
	
	
		--[[
		local pname = "[unknown package]"
		if (package_name ~= nil) then
			pname = package_name
		end
		local rname = "[unknown resource]"
		if (resource_name ~= nil)  then
			log(tostring(resource_name))
			log(inspect(getmetatable(resource_name)))
			log(hashlist_for_the_poor[resource_name:key()])
			if ((resource_name['key'] ~= nil) and (resource_name:key() ~= nil)) then
				rname = hashlist_for_the_poor[resource_name:key()]
			end
		end
		
		local rtype = "[unknown resource type]"
		if (resource_type ~= nil) then
			log(tostring(resource_type))
			log(hashlist_for_the_poor[resource_type])
		end
		if ((resource_type ~= nil) and (resource_type['key'] ~= nil) and (resource_type:key() ~= nil)) then
			rtype = hashlist_for_the_poor[resource_type:key()]
		end
		--] ]
		
		
		local pname = "[unknown package]"
		if (package_name ~= nil) then
			pname = tostring(package_name)
		end
		
		local rname = "[unknown resource]"
		if ((resource_name ~= nil) and (resource_name['key'] ~= nil) and (resource_name:key() ~= nil)) then
			if (hashlist_for_the_poor[resource_name:key()] ~= nil) then
				rname = tostring(hashlist_for_the_poor[resource_name:key()])
			end
		end
		
		local rtype = "[unknown resource type]"
		if ((resource_type ~= nil) and (resource_type['key'] ~= nil) and (resource_type:key() ~= nil)) then
			if (hashlist_for_the_poor[resource_type:key()] ~= nil) then
				rtype = tostring(hashlist_for_the_poor[resource_type:key()])
			end
		end
		local key = rname .. "." .. rtype .. "," .. pname
	
		HangFinder:logLoadStart(key)
	end
)


-- printout whenever done loading an asset
Hooks:PostHook(
	DynamicResourceManager,
	"clbk_resource_loaded",
	"hangfinder_DRM_clbk_resource_loaded", 
	function(self, status, resource_type, resource_name, package_name)
	
	
		--[[
		local pname = "[unknown package]"
		if (package_name ~= nil) then
			pname = package_name
		end
		local rname = "[unknown resource]"
		if ((resource_name ~= nil) and (resource_name['key'] ~= nil) and (resource_name:key() ~= nil)) then
			rname = resource_name:key()
		end
		--[ [
		local rtype = "[unknown resource type]"
		if (resource_type ~= nil) then
			log(inspect(getmetatable(resource_type)))
		end
		if ((resource_type ~= nil) and (resource_type['key'] ~= nil) and (resource_type:key() ~= nil)) then
			rtype = resource_type:key()
		end
		--] ]
		
		local pname = "[unknown package]"
		if (package_name ~= nil) then
			pname = tostring(package_name)
		end
		
		local rname = "[unknown resource]"
		if ((resource_name ~= nil) and (resource_name['key'] ~= nil) and (resource_name:key() ~= nil)) then
			if (hashlist_for_the_poor[resource_name:key()] ~= nil) then
				rname = tostring(hashlist_for_the_poor[resource_name:key()])
			end
		end
		
		local rtype = "[unknown resource type]"
		if ((resource_type ~= nil) and (resource_type['key'] ~= nil) and (resource_type:key() ~= nil)) then
			if (hashlist_for_the_poor[resource_type:key()] ~= nil) then
				rtype = tostring(hashlist_for_the_poor[resource_type:key()])
			end
		end
		
		local key = rname .. "." .. rtype .. "," .. pname
		
		HangFinder:logLoadEnd(key)
	end
)
--]]