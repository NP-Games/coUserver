part of coUserver;

//handle player update events
class StreetUpdateHandler
{
	static Map<String, Street> streets = new Map();
	static Timer timer = new Timer.periodic(new Duration(seconds: 1), (Timer timer) => simulateStreets());
	
	StreetUpdateHandler(WebSocket ws)
	{		
		ws.listen((message)
		{
			processMessage(ws, message);
	    }, 
		onError: (error)
		{
			cleanupList(ws);
		}, 
		onDone: ()
		{
			cleanupList(ws);
		});
		
		//querying the isActive seems to spark the timer to start
		//otherwise it does not start from the static declaration above
		timer.isActive;
	}
	
	static void simulateStreets()
	{
		List<String> toRemove = [];
		streets.forEach((String streetName, Street street)
		{
			Iterable nonNull = street.occupants.where((WebSocket socket) => socket != null);
			if(nonNull.length > 0) //only simulate street with someone on it
			{
				street.plants.forEach((String id, Plant plant) => plant.update());
				street.quoins.forEach((String id, Quoin quoin) => quoin.update());
				street.npcs.forEach((String id, NPC npc) => npc.update());
				
				Map<String,List> updates = {"quoins":[],"npcs":[],"plants":[]};
				street.quoins.forEach((String id, Quoin quoin) => updates["quoins"].add(quoin.getMap()));
				street.npcs.forEach((String id, NPC npc) => updates["npcs"].add(npc.getMap()));
				street.plants.forEach((String id, Plant plant) => updates["plants"].add(plant.getMap()));
				
				street.occupants.forEach((WebSocket socket)
    			{
    				if(socket != null)
    					socket.add(JSON.encode(updates));
    			});
			}
			else
				toRemove.add(street.label);
		});
		
		//clean up memory of streets where no players currently are
		//in the future, I imagine this is where the street would be saved to the database
		toRemove.forEach((String label) => streets.remove(label));
	}
	
	void cleanupList(WebSocket ws)
	{
		//find and remove ws from whichever street has it
		streets.forEach((String streetName, Street street)
		{
			int index = street.occupants.indexOf(ws);
			if(index > -1)
				street.occupants[index] = null;
		});
	}
	
	void processMessage(WebSocket ws, String message)
	{
		//we should receive 3 kinds of messages:
		//player enters street, player exits street, player interacts with object
		//everything else will be outgoing
		try
		{
			Map map = JSON.decode(message);
			String streetName = map["streetName"];
			String username = map["username"];
			
			//if the street doesn't yet exist, create it (maybe it got stored baack to the datastore)
			if(!streets.containsKey(streetName))
			{
				streets[streetName] = new Street(streetName,map['tsid']);
				print("${new DateTime.now()} Loaded $streetName (${map['tsid']}) into memory.");
			}
			
			if(map["remove"] != null)
			{
				if(map["type"] == "quoin")
				{
					if(streets[streetName].quoins[map["remove"]] != null)
						streets[streetName].quoins[map["remove"]].setCollected();
				}
				
				return;
			}
			if(map["callMethod"] != null)
			{
				var entity = streets[streetName].entityMaps[map['type']][map['id']];
				if(entity != null)
				{
					print("user $username calling ${map['callMethod']} on ${entity.id} in $streetName (${map['tsid']})");
					InstanceMirror entityMirror = reflect(entity);
					List arguments = [];
					if(map['arguments'] != null)
						arguments = map['arguments'];
                    entityMirror.invoke(new Symbol(map['callMethod']),arguments,{#userSocket:ws});
				}
			}
			
			if(map["message"] == "joined")
			{
				print("(${new DateTime.now()}) ${map['username']} joined $streetName");
				streets[streetName].occupants.add(ws);
			}
			else if(map["message"] == "left")
				cleanupList(ws);
		}
		catch(error)
		{
			print("(${new DateTime.now()}) Error processing message: $error");
		}
	}
}