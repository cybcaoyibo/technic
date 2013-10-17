-- IC2 Style Energy network manager
-- cybcaoyibo@126.com

--TODO: octant tree for bounding box
--TODO: linked list replacement for nodes
--TODO: linked list replacement for circuits

--[==[

====== data structure ======

node
{
	int id
	vector3 pos
	int XN, XP, YN, YP, ZN, ZP
	int type //0: producer, 1: receiver, 2: battery, 3: cable
	boolean XNc, XPc, YNc, YPc, ZNc, ZPc
}

path
{
	int receiver_id
	int total_loss
	vector<vector3> cables
}

subnet
{
	int producer_id
	vector<path> paths
}

circuit
{
	int id
	vector3 bbmin
	vector3 bbmax
	vector<node> nodes
	map<int, subnet> subnets
}

world
{
	vector<circuit> circuits
	int version
}

]==]

local json = (loadfile (technic.modpath.."/dkjson.lua"))();

technic.energy = {};
technic.energy.world = {circuits = {}, version = 1};

function technic.energy.get_save_file_name()
	return minetest.get_worldpath() .. "/technic_energy.txt";
end

function technic.energy.get_save_backup_file_name()
	return minetest.get_worldpath() .. "/technic_energy.txt.old";
end

function technic.energy.save()
	os.remove(technic.energy.get_save_backup_file_name());
	os.rename(technic.energy.get_save_file_name(), technic.energy.get_save_backup_file_name());
	local file = io.open(technic.energy.get_save_file_name(), "w");
	file:write(json.encode(technic.energy.world));
	file:close();
end

function technic.energy.load()
	local file = io.open(technic.energy.get_save_file_name(), "r");
	if(file == nil) then return false end;
	local content = file:read("*a");
	file:close();
	if(content == nil) then return false end;
	local tmp = json.decode(content);
	if(tmp == nil) then return false end;
	if(type(tmp) ~= "table") then return false end;
	if(tmp.version == nil) then return false end;
	if(type(tmp.version) ~= "number") then return false end;
	if(tmp.version ~= 1) then return false end;
	technic.energy.world = tmp;
	return true;
end

local function add_node_broad_test(circuit, x, y, z)
	if(x < circuit.bbmin.x - 1) then return false end;
	if(y < circuit.bbmin.y - 1) then return false end;
	if(z < circuit.bbmin.z - 1) then return false end;
	if(x > circuit.bbmax.x + 1) then return false end;
	if(y > circuit.bbmax.y + 1) then return false end;
	if(z > circuit.bbmax.z + 1) then return false end;
	return true
end

local function add_node_narrow_test(circuit, x, y, z)
	for k, v in ipairs(circuit.nodes) do
		
		--TODO
	end
end

function technic.energy.add_node(x, y, z)
	local possible = {};
	for k, v in ipairs(technic.energy.world.circuits) do
		if(add_node_broad_test(v, x, y, z)) then
			table.insert(possible, v.id);
		end
	end
	--TODO
end

--TODO

if(not technic.energy.load()) then
	print("create new energy network file");
	technic.energy.save();
end
