-- IC2 Style Energy network manager
-- cybcaoyibo@126.com

--TODO: octant tree for bounding box
--TODO: linked list replacement for nodes
--TODO: linked list replacement for circuits

--[==[

====== data structure ======

conn_attrib
{
	//XNc = x- face can connect to other cables/machines, etc..
	boolean XNc, XPc, YNc, YPc, ZNc, ZPc
}

node
{
	int id
	vector3 pos
	int XN, XP, YN, YP, ZN, ZP
	int type //0: producer, 1: receiver, 2: battery, 3: cable
	conn_attrib conn_attrib
	float loss //only for cables
	int max_packet //only for cables
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

local function find_node_broad_test(circuit, x, y, z)
	if(x < circuit.bbmin.x) then return false end;
	if(y < circuit.bbmin.y) then return false end;
	if(z < circuit.bbmin.z) then return false end;
	if(x > circuit.bbmax.x) then return false end;
	if(y > circuit.bbmax.y) then return false end;
	if(z > circuit.bbmax.z) then return false end;
	return true
end

local function add_node_narrow_test(circuit, x, y, z, conn_attrib)
	for k, v in ipairs(circuit.nodes) do
		if(v.conn_attrib.XNc and conn_attrib.XPc and x == v.pos.x - 1 and y == v.pos.y and z == v.pos.z) then return true end;
		if(v.conn_attrib.XPc and conn_attrib.XNc and x == v.pos.x + 1 and y == v.pos.y and z == v.pos.z) then return true end;
		if(v.conn_attrib.YNc and conn_attrib.YPc and x == v.pos.x and y == v.pos.y - 1 and z == v.pos.z) then return true end;
		if(v.conn_attrib.YPc and conn_attrib.YNc and x == v.pos.x and y == v.pos.y + 1 and z == v.pos.z) then return true end;
		if(v.conn_attrib.ZNc and conn_attrib.ZPc and x == v.pos.x and y == v.pos.y and z == v.pos.z - 1) then return true end;
		if(v.conn_attrib.ZPc and conn_attrib.ZNc and x == v.pos.x and y == v.pos.y and z == v.pos.z + 1) then return true end;
	end
	return false;
end

local function find_node_narrow_test(circuit, x, y, z)
	for k, v in ipairs(circuit.nodes) do
		if(x == v.pos.x and y == v.pos.y and z == v.pos.z) then return v.id; end;
	end
	return nil;
end

local function transcript_node(x, y, z)
	--TODO
end

local function new_circuit()
	return {id = 0,
			bbmin = {x = 0, y = 0, z = 0},
			bbmax = {x = 0, y = 0, z = 0},
			nodes = {},
			subnets = {}}
end

local function rebuild_circuit(id)
	--TODO
end

function technic.energy.remove_node(x, y, z)
	local possible_broad = {};
	local possible_narrow = {};
	for k, v in ipairs(technic.energy.world.circuits) do
		if(add_node_broad_test(v, x, y, z)) then
			table.insert(possible_broad, v.id);
		end
	end
	assert(table.getn(possible_broad) <= 1);
	if(table.getn(possible_broad) == 0) then
		print("energy.lua: attempt to remove a node which is unadded (1) (" .. x .. ", ".. y .. ", " .. z .. ")");
		return;
	end
	local node_id = find_node_narrow_test(technic.energy.world.circuits[possible_narrow[1]], x, y, z);
	if(node_id == nil) then
		print("energy.lua: attempt to remove a node which is unadded (2) (" .. x .. ", ".. y .. ", " .. z .. ")");
		return;
	end
	local other_nodes = {};
	local i = 1;
	for k, v in ipairs(technic.energy.world.circuits[possible_narrow[1]].nodes) do
		if(v.id ~= node_id) then
			table.insert(other_nodes, v);
		else
			v.id = i;
			i = i + 1;
		end
	end
	assert(table.getn(other_nodes) == table.getn(technic.energy.world.circuits[possible_narrow[1]].nodes) - 1);
	technic.energy.world.circuits[possible_narrow[1]].nodes = other_nodes;
	rebuild_circuit(possible_narrow[1]);
end

function technic.energy.add_node(x, y, z)
	local node = transcript_node(x, y, z);
	if(node == nil) then
		print("energy.lua: attempt to add a node in unloaded area (" .. x .. ", ".. y .. ", " .. z .. ")");
		return
	end
	local possible_broad = {};
	local possible_narrow = {};
	for k, v in ipairs(technic.energy.world.circuits) do
		if(add_node_broad_test(v, x, y, z)) then
			table.insert(possible_broad, v.id);
		end
	end
	for k, v in ipairs(possible_broad) do
		if(add_node_narrow_test(technic.energy.world.circuits[v], x, y, z, node.conn_attrib)) then
			table.insert(possible_narrow, v);
		end
	end
	if(table.getn(possible_narrow) == 0) then
		local circuit = new_circuit();
		circuit.id = table.getn(technic.energy.world.circuits) + 1;
		technic.energy.world.circuits[circuit.id] = circuit;
		node.id = 1;
		technic.energy.world.circuits[circuit.id].nodes[1] = node;
		rebuild_circuit(circuit.id);
	elseif(table.getn(possible_narrow) == 1) then
		node.id = table.getn(technic.energy.world.circuits[possible_narrow[1]].nodes) + 1;
		table.insert(technic.energy.world.circuits[possible_narrow[1]].nodes, node);
		rebuild_circuit(possible_narrow[1]);
	else
		--reindex other circuits
		local chosen_circuits = {};
		local other_circuits = {};
		local i_for_other_circuits = 1;
		for k, v in ipairs(technic.energy.world.circuits) do
			local hit = false;
			for k1, v1 in ipairs(possible_narrow) do
				if(v1 == v.id) then
					hit = true;
					break;
				end
			end
			if(hit) then
				table.insert(chosen_circuits, v);
			else
				v.id = i_for_other_circuits;
				table.insert(other_circuits, v);
				i_for_other_circuits = i_for_other_circuits + 1;
			end
		end
		assert(table.getn(chosen_circuits) == table.getn(possible_narrow));
		--combine chosen circuits
		local new_circuit;
		for k, v in ipairs(chosen_circuits) do
			if(k == 1) then
				new_circuit = v;
			else
				for k1, v1 in ipairs(v.nodes) do
					table.insert(new_circuit.nodes, v1);
				end
			end
		end
		--reindex nodes
		for k, v in ipairs(new_circuit.nodes) do
			v.id = k;
		end
		--add and rebuild
		new_circuit.id = table.getn(technic.energy.world.circuits + 1);
		table.insert(technic.energy.world.circuits, new_circuit);
		rebuild_circuit(new_circuit.id);
	end
end

--TODO

if(not technic.energy.load()) then
	technic.energy.save();
end
