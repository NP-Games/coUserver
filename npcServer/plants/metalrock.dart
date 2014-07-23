part of coUserver;

class MetalRock extends Rock
{
	MetalRock(String id, int x, int y) : super(id,x,y)
	{
		type = "Metal Rock";
        		
		states = 
			{
				"5-4-3-2-1" : new Spritesheet("5-4-3-2-1","http://c2.glitch.bz/items/2012-12-06/rock_metal_x1_5_x1_4_x1_3_x1_2_x1_1__1_png_1354832615.png",685,100,137,100,5,false)
			};
		currentState = states['5-4-3-2-1'];
     	state = new Random().nextInt(currentState.numFrames);
     	maxState = 0;
	}
	
	void mine({WebSocket userSocket})
	{
		super.mine(userSocket:userSocket);
        		
		//give the player the 'fruits' of their labor
		Map map = {};
		map['giveItem'] = "true";
		map['item'] = new ChunkOfMetalRock().getMap();
		map['num'] = 1;
		map['fromObject'] = id;
		userSocket.add(JSON.encode(map));
	}
}