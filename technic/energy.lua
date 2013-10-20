-- IC2 Style Energy network manager
-- cybcaoyibo@126.com

--OPTIONAL:
--octant tree for bounding box
--linked list replacement for nodes
--linked list replacement for circuits
--separate network when disconnect

--[==[

====== data structure ======

conn_attrib
{
	//XNc = x- face can connect to other cables/machines, etc..
	//0: none
	//1: producer
	//2: receiver
	int XNc, XPc, YNc, YPc, ZNc, ZPc
}

node
{
	int id
	vector3 pos
	//adjacent node id (only that can connect to) (0 = null)
	int XN, XP, YN, YP, ZN, ZP
	int type //0: machine, 1: cable
	conn_attrib conn_attrib
	float loss //only for cables
	int max_packet //only for cables (-1 = inf)
}

path
{
	int to_side //energy reached which receiver side of the machine?
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
	vector<int> machines //all machines in the circuit
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
	file:write(json.encode(technic.energy.world, {indent = true}));
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
		if    (v.conn_attrib.XNc > 0 and conn_attrib.XPc > 0 and x == v.pos.x - 1 and y == v.pos.y and z == v.pos.z) then table.insert(adjs, {v, 1});
		elseif(v.conn_attrib.XPc > 0 and conn_attrib.XNc > 0 and x == v.pos.x + 1 and y == v.pos.y and z == v.pos.z) then table.insert(adjs, {v, 2});
		elseif(v.conn_attrib.YNc > 0 and conn_attrib.YPc > 0 and x == v.pos.x and y == v.pos.y - 1 and z == v.pos.z) then table.insert(adjs, {v, 3});
		elseif(v.conn_attrib.YPc > 0 and conn_attrib.YNc > 0 and x == v.pos.x and y == v.pos.y + 1 and z == v.pos.z) then table.insert(adjs, {v, 4});
		elseif(v.conn_attrib.ZNc > 0 and conn_attrib.ZPc > 0 and x == v.pos.x and y == v.pos.y and z == v.pos.z - 1) then table.insert(adjs, {v, 5});
		elseif(v.conn_attrib.ZPc > 0 and conn_attrib.ZNc > 0 and x == v.pos.x and y == v.pos.y and z == v.pos.z + 1) then table.insert(adjs, {v, 6}); end;
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
	dprint("transcript_node(" .. x .. ", " .. y .. ", " .. z .. ")");
	local node = {};
	node.id = 0;
	node.pos = {x = x, y = y, z = z};
	node.XN = 0;
	node.XP = 0;
	node.YN = 0;
	node.YP = 0;
	node.ZN = 0;
	node.ZP = 0;
	local node_mt = minetest.get_node_or_nil(node.pos);
	local cable_tier = technic.get_cable_tier(node_mt.name);
	if(cable_tier ~= nil) then
		node.loss = 1; --TODO
		node.type = 1;
		node.max_packet = -1; --TODO
		node.conn_attrib = {XNc = 1, XPc = 1, YNc = 1, YPc = 1, ZNc = 1, ZPc = 1};
		dprint("adding cable: " .. cable_tier);
	else
		dprint("adding machine: " .. node_mt.name);
		local machine_tier = nil;
		for k, v in pairs(technic.machines) do
			machine_tier = v[node_mt.name];
			if(machine_tier ~= nil) then
				break;
			end
		end
		node.type = 0;
		node.conn_attrib = {XNc = 1, XPc = 1, YNc = 1, YPc = 1, ZNc = 1, ZPc = 1}; --TODO
	end
	return node;
end

local function new_circuit()
	return {id = 0,
			bbmin = {x = 0, y = 0, z = 0},
			bbmax = {x = 0, y = 0, z = 0},
			nodes = {}, machines = {},
			subnets = {}}
end

local function build_subnet(circuit, nid)
	
	local paths = {};
	
	--Dijkstra's algorithm
	
	--A: distance list
	--B: unprocessed list
	--C: previous list
	--D: out list
	--E: "to_side" list
	local A, B, C, D, E = {}, {}, {}, {}, {};
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
		--for producer, only producer faces are allowed
		if now == nid then
			if(circuit.nodes[now].XN ~= 0 and circuit.nodes[now].conn_attrib.XNc == 1) then table.insert(neighbors, circuit.nodes[now].XN) end
			if(circuit.nodes[now].XP ~= 0 and circuit.nodes[now].conn_attrib.XPc == 1) then table.insert(neighbors, circuit.nodes[now].XP) end
			if(circuit.nodes[now].YN ~= 0 and circuit.nodes[now].conn_attrib.YNc == 1) then table.insert(neighbors, circuit.nodes[now].YN) end
			if(circuit.nodes[now].YP ~= 0 and circuit.nodes[now].conn_attrib.YPc == 1) then table.insert(neighbors, circuit.nodes[now].YP) end
			if(circuit.nodes[now].ZN ~= 0 and circuit.nodes[now].conn_attrib.ZNc == 1) then table.insert(neighbors, circuit.nodes[now].ZN) end
			if(circuit.nodes[now].ZP ~= 0 and circuit.nodes[now].conn_attrib.ZPc == 1) then table.insert(neighbors, circuit.nodes[now].ZP) end
			assert(table.getn(neighbors) == 1);
		--for cable, all connectable face are allowed
		elseif circuit.nodes[now].type == 1 then
			if(circuit.nodes[now].XN ~= 0) then table.insert(neighbors, circuit.nodes[now].XN) end
			if(circuit.nodes[now].XP ~= 0) then table.insert(neighbors, circuit.nodes[now].XP) end
			if(circuit.nodes[now].YN ~= 0) then table.insert(neighbors, circuit.nodes[now].YN) end
			if(circuit.nodes[now].YP ~= 0) then table.insert(neighbors, circuit.nodes[now].YP) end
			if(circuit.nodes[now].ZN ~= 0) then table.insert(neighbors, circuit.nodes[now].ZN) end
			if(circuit.nodes[now].ZP ~= 0) then table.insert(neighbors, circuit.nodes[now].ZP) end
		--for receiver, only receiver faces are allowed
		elseif circuit.nodes[now].type == 0 then
			if(circuit.nodes[now].XN ~= 0 and circuit.nodes[now].conn_attrib.XNc == 2) then table.insert(neighbors, circuit.nodes[now].XN) end
			if(circuit.nodes[now].XP ~= 0 and circuit.nodes[now].conn_attrib.XPc == 2) then table.insert(neighbors, circuit.nodes[now].XP) end
			if(circuit.nodes[now].YN ~= 0 and circuit.nodes[now].conn_attrib.YNc == 2) then table.insert(neighbors, circuit.nodes[now].YN) end
			if(circuit.nodes[now].YP ~= 0 and circuit.nodes[now].conn_attrib.YPc == 2) then table.insert(neighbors, circuit.nodes[now].YP) end
			if(circuit.nodes[now].ZN ~= 0 and circuit.nodes[now].conn_attrib.ZNc == 2) then table.insert(neighbors, circuit.nodes[now].ZN) end
			if(circuit.nodes[now].ZP ~= 0 and circuit.nodes[now].conn_attrib.ZPc == 2) then table.insert(neighbors, circuit.nodes[now].ZP) end
		else
			assert(false)
		end
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
						    if circuit.nodes[v].XN = now then E[v] = 1
						elseif circuit.nodes[v].XP = now then E[v] = 2
						elseif circuit.nodes[v].YN = now then E[v] = 3
						elseif circuit.nodes[v].YP = now then E[v] = 4
						elseif circuit.nodes[v].ZN = now then E[v] = 5
						elseif circuit.nodes[v].ZP = now then E[v] = 6
						else assert(false) end
						--receiver is the terminal of the graph, so don't add it to B
					else
						if(A[v] > A[now]) then
							A[v] = A[now];
							C[v] = now;
								if circuit.nodes[v].XN = now then E[v] = 1
							elseif circuit.nodes[v].XP = now then E[v] = 2
							elseif circuit.nodes[v].YN = now then E[v] = 3
							elseif circuit.nodes[v].YP = now then E[v] = 4
							elseif circuit.nodes[v].ZN = now then E[v] = 5
							elseif circuit.nodes[v].ZP = now then E[v] = 6
							else assert(false) end
						end
					end
				end
			end
		end
	end
	
	for i, j in pairs(circuit.machines) do
		--j can be nid if nid is both a producer and a receiver
		if(j ~= nid) then
			--if there is a receiver reached the producer
			if(A[j] ~= nil) then
				local now_path = {};
				now_path.receiver_id = j;
				assert(E[j] ~= nil);
				now_path.to_side = E[j];
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
	end
	
	return paths;
end

local function rebuild_circuit(id)
	local circuit = technic.energy.world.circuits[id];
	assert(table.getn(circuit.nodes) > 0);
	
	--bounding box
	circuit.bbmin.x = circuit.nodes[1].pos.x;
	circuit.bbmin.y = circuit.nodes[1].pos.y;
	circuit.bbmin.z = circuit.nodes[1].pos.z;
	circuit.bbmax.x = circuit.nodes[1].pos.x;
	circuit.bbmax.y = circuit.nodes[1].pos.y;
	circuit.bbmax.z = circuit.nodes[1].pos.z;
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
		if(v.type == 0) then
			table.insert(circuit.machines, v.id)
			table.insert(circuit.subnets, {producer_id = v.id})
		end
	end
	for k, v in ipairs(circuit.subnets) do
		v.paths = build_subnet(circuit, v.producer_id);
	end
end

local function separate_and_rebuild_circuit(cid)
	local circuit = technic.energy.world.circuits[cid];
	local proceeded_nodes = {};
	local function recursive(circuit, now_node, proceeded_nodes, result_nodes)
		if(proceeded_nodes[now_node] == true) then return end
		proceeded_nodes[now_node] = true;
		table.insert(result_nodes, circuit.nodes[now_node]);
		if(circuit.nodes[now_node].XN ~= 0) then recursive(circuit, circuit.nodes[now_node].XN, proceeded_nodes, result_nodes); end;
		if(circuit.nodes[now_node].XP ~= 0) then recursive(circuit, circuit.nodes[now_node].XP, proceeded_nodes, result_nodes); end;
		if(circuit.nodes[now_node].YN ~= 0) then recursive(circuit, circuit.nodes[now_node].YN, proceeded_nodes, result_nodes); end;
		if(circuit.nodes[now_node].YP ~= 0) then recursive(circuit, circuit.nodes[now_node].YP, proceeded_nodes, result_nodes); end;
		if(circuit.nodes[now_node].ZN ~= 0) then recursive(circuit, circuit.nodes[now_node].ZN, proceeded_nodes, result_nodes); end;
		if(circuit.nodes[now_node].ZP ~= 0) then recursive(circuit, circuit.nodes[now_node].ZP, proceeded_nodes, result_nodes); end;
	end
	local new_circuits = {};
	for k, v in ipairs(circuit.nodes) do
		if proceeded_nodes[v.id] ~= true then
			local nc = new_circuit();
			recursive(circuit, v.id, proceeded_nodes, nc.nodes);
			table.insert(new_circuits, nc);
		end
	end
	--TODO: reindex nodes, add to table, rebuild circuits
end

function technic.energy.remove_node(x, y, z)
	local possible_broad = {};
	for k, v in ipairs(technic.energy.world.circuits) do
		if(add_node_broad_test(v, x, y, z)) then
			table.insert(possible_broad, v.id);
		end
	end
	if(table.getn(possible_broad) == 0) then
		print("energy.lua: attempt to remove a node which is unadded (1) (" .. x .. ", ".. y .. ", " .. z .. ")");
		return;
	end
	local node_id = nil;
	local cid = 0;
	for k, v in ipairs(possible_broad) do
		node_id = find_node_narrow_test(technic.energy.world.circuits[v], x, y, z);
		if(node_id ~= nil) then
			cid = v;
			break;
		end
	end
	if(node_id == nil) then
		print("energy.lua: attempt to remove a node which is unadded (2) (" .. x .. ", ".. y .. ", " .. z .. ")");
		return;
	end
	if(table.getn(technic.energy.world.circuits[cid].nodes) > 1) then
		--break adjacency
		local adjacency_broken = 0;
		do
			local node = technic.energy.world.circuits[cid].nodes[node_id];
			if(node.XN ~= 0) then technic.energy.world.circuits[cid].nodes[node.XN].XP = 0; adjacency_broken = adjacency_broken + 1 end;
			if(node.XP ~= 0) then technic.energy.world.circuits[cid].nodes[node.XP].XN = 0; adjacency_broken = adjacency_broken + 1 end;
			if(node.YN ~= 0) then technic.energy.world.circuits[cid].nodes[node.YN].YP = 0; adjacency_broken = adjacency_broken + 1 end;
			if(node.YP ~= 0) then technic.energy.world.circuits[cid].nodes[node.YP].YN = 0; adjacency_broken = adjacency_broken + 1 end;
			if(node.ZN ~= 0) then technic.energy.world.circuits[cid].nodes[node.ZN].ZP = 0; adjacency_broken = adjacency_broken + 1 end;
			if(node.ZP ~= 0) then technic.energy.world.circuits[cid].nodes[node.ZP].ZN = 0; adjacency_broken = adjacency_broken + 1 end;
		end
		assert(adjacency_broken > 0);
		--remove node from table
		local other_nodes = {};
		local i = 1;
		for k, v in ipairs(technic.energy.world.circuits[cid].nodes) do
			if(v.id ~= node_id) then
				v.id = i;
				--reindex adjacency
				if(v.XN > node_id) then v.XN = v.XN - 1 end;
				if(v.XP > node_id) then v.XP = v.XP - 1 end;
				if(v.YN > node_id) then v.YN = v.YN - 1 end;
				if(v.YP > node_id) then v.YP = v.YP - 1 end;
				if(v.ZN > node_id) then v.ZN = v.ZN - 1 end;
				if(v.ZP > node_id) then v.ZP = v.ZP - 1 end;
				i = i + 1;
				table.insert(other_nodes, v);
			end
		end
		assert(table.getn(other_nodes) == table.getn(technic.energy.world.circuits[cid].nodes) - 1);
		technic.energy.world.circuits[cid].nodes = other_nodes;
		dprint("node removed from: " .. cid);
		if(adjacency_broken > 1) then
			--removed node was not a terminal of the circuit
			separate_and_rebuild_circuit(cid);
		else
			rebuild_circuit(cid);
		end
	else
		local other_circuits = {};
		local i = 1;
		for k, v in ipairs(technic.energy.world.circuits) do
			if(v.id ~= cid) then
				v.id = i;
				i = i + 1;
				table.insert(other_circuits, v);
			end
		end
		technic.energy.world.circuits = other_circuits;
		dprint("circuit destroyed: " .. cid);
	end
	technic.energy.save();
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
		dprint("new circuit: " .. circuit.id);
		rebuild_circuit(circuit.id);
	elseif(table.getn(possible_narrow) == 1) then
		--(need to add to a existed circuit)
		
		node.id = table.getn(technic.energy.world.circuits[possible_narrow[1].cid].nodes) + 1;
		--add adjacency
		for k, v in ipairs(possible_narrow[1].adjs) do
			    if(v[2] == 1) then v[1].XP = node.id; node.XN = v[1].id;
			elseif(v[2] == 2) then v[1].XN = node.id; node.XP = v[1].id;
			elseif(v[2] == 3) then v[1].YP = node.id; node.YN = v[1].id;
			elseif(v[2] == 4) then v[1].YN = node.id; node.YP = v[1].id;
			elseif(v[2] == 5) then v[1].ZP = node.id; node.ZN = v[1].id;
			elseif(v[2] == 6) then v[1].ZN = node.id; node.ZP = v[1].id;
			else assert(false); end;
		end
		--add node to table
		table.insert(technic.energy.world.circuits[possible_narrow[1].cid].nodes, node);
		dprint("add to circuit: " .. possible_narrow[1].cid);
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
				if(v1.cid == v.id) then
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
		dprint("combined: " .. table.getn(chosen_circuits) .. " circuits");
		assert(table.getn(chosen_circuits) == table.getn(possible_narrow));
		--replace
		technic.energy.world.circuits = other_circuits;
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
					if(v1[2] == 1) then v1[1].XP = node.id; node.XN = v1[1].id;
				elseif(v1[2] == 2) then v1[1].XN = node.id; node.XP = v1[1].id;
				elseif(v1[2] == 3) then v1[1].YP = node.id; node.YN = v1[1].id;
				elseif(v1[2] == 4) then v1[1].YN = node.id; node.YP = v1[1].id;
				elseif(v1[2] == 5) then v1[1].ZP = node.id; node.ZN = v1[1].id;
				elseif(v1[2] == 6) then v1[1].ZN = node.id; node.ZP = v1[1].id;
				else assert(false); end;
			end
		end
		--add node to table
		new_circuit.nodes[node.id] = node;
		--add to table, add adjacency and rebuild
		new_circuit.id = table.getn(technic.energy.world.circuits) + 1;
		table.insert(technic.energy.world.circuits, new_circuit);
		dprint("to: " .. new_circuit.id);
		rebuild_circuit(new_circuit.id);
	end
	technic.energy.save();
end

--TODO

if(not technic.energy.load()) then
	technic.energy.save();
end
