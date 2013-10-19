-- IC2 Style Energy network manager
-- cybcaoyibo@126.com

--OPTIONAL:
--octant tree for bounding box
--linked list replacement for nodes
--linked list replacement for circuits

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
	//adjacent node id (only that can connect to) (0 = null)
	int XN, XP, YN, YP, ZN, ZP
	int type //0: producer, 1: receiver, 2: both, 3: cable
	conn_attrib conn_attrib
	float loss //only for cables
	int max_packet //only for cables
}

path
{
	int receiver_id
	int total_loss
	vector<int> cables //value = node_id, (from receiver to producer)
}

subnet
{
	int producer_id
	map<int, path> paths //key = receiver_id
}

circuit
{
	int id
	vector3 bbmin
	vector3 bbmax
	vector<node> nodes
	map<int, subnet> subnets //key = producer_id
	vector<int> receivers //all receivers in the circuit
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

--debug print
local function dprint(...)
	local args = {...};
	print(unpack(args));
end

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
	--adjs = {{node, which_face}, ...}
	--which_face: orient from the node to be added
	local adjs = {};
	for k, v in ipairs(circuit.nodes) do
		if    (v.conn_attrib.XNc and conn_attrib.XPc and x == v.pos.x - 1 and y == v.pos.y and z == v.pos.z) then table.insert(adjs, {v, 1});
		elseif(v.conn_attrib.XPc and conn_attrib.XNc and x == v.pos.x + 1 and y == v.pos.y and z == v.pos.z) then table.insert(adjs, {v, 2});
		elseif(v.conn_attrib.YNc and conn_attrib.YPc and x == v.pos.x and y == v.pos.y - 1 and z == v.pos.z) then table.insert(adjs, {v, 3});
		elseif(v.conn_attrib.YPc and conn_attrib.YNc and x == v.pos.x and y == v.pos.y + 1 and z == v.pos.z) then table.insert(adjs, {v, 4});
		elseif(v.conn_attrib.ZNc and conn_attrib.ZPc and x == v.pos.x and y == v.pos.y and z == v.pos.z - 1) then table.insert(adjs, {v, 5});
		elseif(v.conn_attrib.ZPc and conn_attrib.ZNc and x == v.pos.x and y == v.pos.y and z == v.pos.z + 1) then table.insert(adjs, {v, 6}); end;
	end
	return adjs;
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
			nodes = {}, receivers = {},
			subnets = {}}
end

local function build_subnet(circuit, nid)
	
	local paths = {};
	
	--Dijkstra's algorithm
	
	--A: distance list
	--B: unprocessed list
	--C: previous list
	--D: out list
	local A, B, C, D = {}, {}, {}, {};
	A[nid] = 0;
	B[1] = nid;
	
	while true do
		if(table.getn(B) == 0) then break end
		--get the smallest one in B
		local selected_B = 1;
		for k, v in ipairs(B) do
			if(A[v] < A[B[selected_B]]) then
				selected_B = k;
			end
		end
		--mark it out and remove it from B
		local now = B[selected_B];
		D[now] = true;
		table.remove(B, selected_B);
		--list all connected nodes
		local neighbors = {};
		if(circuit.nodes[now].XN ~= 0) then table.insert(neighbors, circuit.nodes[now].XN) end
		if(circuit.nodes[now].XP ~= 0) then table.insert(neighbors, circuit.nodes[now].XP) end
		if(circuit.nodes[now].YN ~= 0) then table.insert(neighbors, circuit.nodes[now].YN) end
		if(circuit.nodes[now].YP ~= 0) then table.insert(neighbors, circuit.nodes[now].YP) end
		if(circuit.nodes[now].ZN ~= 0) then table.insert(neighbors, circuit.nodes[now].ZN) end
		if(circuit.nodes[now].ZP ~= 0) then table.insert(neighbors, circuit.nodes[now].ZP) end
		--process all connected nodes
		for k, v in ipairs(neighbors) do
			if(D[v] ~= true) then
				if(circuit.nodes[v].type == 3) then
					--(cable)
					local new_distance = A[now] + circuit.nodes[v].loss;
					if(A[v] == nil) then
						A[v] = new_distance;
						C[v] = now;
						table.insert(B, v);
					else
						if(A[v] > new_distance) then
							A[v] = new_distance;
							C[v] = now;
						end
					end
				elseif(circuit.nodes[v].type == 1 or circuit.nodes[v].type == 2) then
					--(receiver)
					if(A[v] == nil) then
						A[v] = A[now];
						C[v] = now;
						--receiver is the terminal of the graph, so don't add it to B
					else
						if(A[v] > A[now]) then
							A[v] = A[now];
							C[v] = now;
						end
					end
				end
			end
		end
	end
	
	for i, j in pairs(circuit.receivers) do
		--j can be nid if nid is both a producer and a receiver
		if(j ~= nid) then
			assert(A[j] ~= nil);
			local now_path = {};
			now_path.receiver_id = j;
			now_path.total_loss = A[j];
			now_path.cables = {};
			
			--reverse iteration of cables
			local now_cable = j;
			while true do
				assert(C[now_cable] ~= nil);
				now_cable = C[now_cable];
				if(now_cable == nid) then break end;
				table.insert(now_path.cables, now_cable);
			end
			
			paths[j] = now_path;
		end
	end
	
	return paths;
end

local function rebuild_circuit(id)
	local circuit = technic.energy.world.circuits[id];
	assert(table.getn(circuit.nodes) > 0);
	
	--bounding box
	circuit.bbmin = circuit.nodes[1].pos;
	circuit.bbmax = circuit.nodes[1].pos;
	if(table.getn(circuit.nodes) > 1) then
		for i = 2, table.getn(circuit.nodes) do
			local node = circuit.nodes[i];
			if(node.pos.x < circuit.bbmin.x) then circuit.bbmin.x = node.pos.x end;
			if(node.pos.y < circuit.bbmin.y) then circuit.bbmin.y = node.pos.y end;
			if(node.pos.z < circuit.bbmin.z) then circuit.bbmin.z = node.pos.z end;
			if(node.pos.x > circuit.bbmax.x) then circuit.bbmax.x = node.pos.x end;
			if(node.pos.y > circuit.bbmax.y) then circuit.bbmax.y = node.pos.y end;
			if(node.pos.z > circuit.bbmax.z) then circuit.bbmax.z = node.pos.z end;
		end
	end
	
	--subnets
	circuit.subnets = {};
	for k, v in ipairs(circuit.nodes) do
		if(v.type == 0 or v.type == 2) then table.insert(circuit.subnets, {producer_id = v.id}) end
		if(v.type == 1 or v.type == 2) then table.insert(circuit.receivers, v.id) end
	end
	for k, v in ipairs(circuit.subnets) do
		v.paths = build_subnet(circuit, v.producer_id);
	end
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
	if(table.getn(technic.energy.world.circuits[possible_narrow[1]].nodes) > 0) then
		--break adjacency
		do
			local node = technic.energy.world.circuits[possible_narrow[1]].nodes[node_id];
			if(node.XN ~= 0) then technic.energy.world.circuits[possible_narrow[1]].nodes[node.XN].XP = 0 end;
			if(node.XP ~= 0) then technic.energy.world.circuits[possible_narrow[1]].nodes[node.XP].XN = 0 end;
			if(node.YN ~= 0) then technic.energy.world.circuits[possible_narrow[1]].nodes[node.YN].YP = 0 end;
			if(node.YP ~= 0) then technic.energy.world.circuits[possible_narrow[1]].nodes[node.YP].YN = 0 end;
			if(node.ZN ~= 0) then technic.energy.world.circuits[possible_narrow[1]].nodes[node.ZN].ZP = 0 end;
			if(node.ZP ~= 0) then technic.energy.world.circuits[possible_narrow[1]].nodes[node.ZP].ZN = 0 end;
		end
		--remove node from table
		local other_nodes = {};
		local i = 1;
		for k, v in ipairs(technic.energy.world.circuits[possible_narrow[1]].nodes) do
			if(v.id ~= node_id) then
				v.id = i;
				i = i + 1;
				table.insert(other_nodes, v);
			end
		end
		assert(table.getn(other_nodes) == table.getn(technic.energy.world.circuits[possible_narrow[1]].nodes) - 1);
		technic.energy.world.circuits[possible_narrow[1]].nodes = other_nodes;
		rebuild_circuit(possible_narrow[1].cid);
	else
		local other_circuits = {};
		local i = 1;
		for k, v in ipairs(technic.energy.world.circuits) do
			if(v.id ~= possible_narrow[1]) then
				v.id = i;
				i = i + 1;
				table.insert(other_circuits, v);
			end
		end
		assert(table.getn(other_circuits) == table.getn(technic.energy.world.circuits));
		technic.energy.world.circuits = other_circuits;
	end
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
		local rst = add_node_narrow_test(technic.energy.world.circuits[v], x, y, z, node.conn_attrib);
		if(table.getn(rst) > 0) then
			table.insert(possible_narrow, {cid = v, adjs = rst});
		end
	end
	if(table.getn(possible_narrow) == 0) then
		--(need to create a new circuit)
		
		local circuit = new_circuit();
		circuit.id = table.getn(technic.energy.world.circuits) + 1;
		technic.energy.world.circuits[circuit.id] = circuit;
		node.id = 1;
		technic.energy.world.circuits[circuit.id].nodes[1] = node;
		rebuild_circuit(circuit.id);
	elseif(table.getn(possible_narrow) == 1) then
		--(need to add to a existed circuit)
		
		node.id = table.getn(technic.energy.world.circuits[possible_narrow[1].cid].nodes) + 1;
		--add adjacency
		for k, v in ipairs(possible_narrow[1].adjs) do
			    if(v[2] == 0) then v[1].XP = node.id; node.XN = v[1].id;
			elseif(v[2] == 1) then v[1].XN = node.id; node.XP = v[1].id;
			elseif(v[2] == 2) then v[1].YP = node.id; node.YN = v[1].id;
			elseif(v[2] == 3) then v[1].YN = node.id; node.YP = v[1].id;
			elseif(v[2] == 4) then v[1].ZP = node.id; node.ZN = v[1].id;
			elseif(v[2] == 5) then v[1].ZN = node.id; node.ZP = v[1].id;
			else assert(false); end;
		end
		--add node to table
		table.insert(technic.energy.world.circuits[possible_narrow[1].cid].nodes, node);
		rebuild_circuit(possible_narrow[1].cid);
	else
		--(need to combine multiple circuits)
		
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
		--new node id
		node.id = table.getn(new_circuit.nodes) + 1;
		--add adjacency
		for k, v in ipairs(possible_narrow) do
			for k1, v1 in ipairs(v.adjs) do
					if(v1[2] == 0) then v1[1].XP = node.id; node.XN = v1[1].id;
				elseif(v1[2] == 1) then v1[1].XN = node.id; node.XP = v1[1].id;
				elseif(v1[2] == 2) then v1[1].YP = node.id; node.YN = v1[1].id;
				elseif(v1[2] == 3) then v1[1].YN = node.id; node.YP = v1[1].id;
				elseif(v1[2] == 4) then v1[1].ZP = node.id; node.ZN = v1[1].id;
				elseif(v1[2] == 5) then v1[1].ZN = node.id; node.ZP = v1[1].id;
				else assert(false); end;
			end
		end
		--add node to table
		new_circuit.nodes[node.id] = node;
		--add to table, add adjacency and rebuild
		new_circuit.id = table.getn(technic.energy.world.circuits + 1);
		table.insert(technic.energy.world.circuits, new_circuit);
		rebuild_circuit(new_circuit.id);
	end
end

--TODO

if(not technic.energy.load()) then
	technic.energy.save();
end
