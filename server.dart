part of coUserver;

IRCRelay relay;
double minClientVersion = 0.12;
PostgreSqlManager dbManager;
Map<String,int> heightsCache = null;
DateTime startDate;
Map<String,Item> items = {};

void main()
{
	int port = 8181;
	try	{port = int.parse(Platform.environment['PORT']);}
	catch (error){port = 8181;}

	dbManager = new PostgreSqlManager(databaseUri, min: 1, max: 9);

	app.addPlugin(getMapperPlugin(dbManager));
	app.addPlugin(getWebSocketPlugin());

	app.setupConsoleLog();
	app.start(port:port, autoCompress:true);

	KeepAlive.start();

	//create items from items.json
	StreetUpdateHandler.loadItems();

	//redstone.dart does not support websockets so we have to listen on a
	//seperate port for those connections :(
	HttpServer.bind('0.0.0.0', 8282).then((HttpServer server)
	{
        //relay = new IRCRelay();

		server.listen((HttpRequest request)
		{
			WebSocketTransformer.upgrade(request).then((WebSocket websocket)
			{
				if(request.uri.path == "/chat")
					ChatHandler.handle(websocket);
				else if(request.uri.path == "/playerUpdate")
					PlayerUpdateHandler.handle(websocket);
				else if(request.uri.path == "/streetUpdate")
					StreetUpdateHandler.handle(websocket);
				else if(request.uri.path == "/metabolics")
					MetabolicsEndpoint.handle(websocket);
			})
			.catchError((error)
			{
				log("error: $error");
			},
			test: (Exception e) => e is! WebSocketException)
			.catchError((error){},test: (Exception e) => e is WebSocketException);
		});

		log('Serving Chat on ${'0.0.0.0'}:8282');
	});

	//useful for making trees speech bubbles appear where they should
	loadHeightsCacheFromDisk();

	//save some server state to the disk every 30 seconds
	new Timer.periodic(new Duration(seconds:30), (Timer t)
	{
		try
		{
			StatBuffer.writeStatsToFile();
			saveHeightsCacheToDisk();
		}
		catch(e)
		{
			log("Problem writing stats to file: $e");
		}
	});

	//Keep track of when the server was started
	startDate = new DateTime.now();
}

PostgreSql get dbConn => app.request.attributes.dbConn;

//add a CORS header to every request
@app.Interceptor(r'/.*')
crossOriginInterceptor()
{
	if (app.request.method == "OPTIONS")
	{
		//overwrite the current response and interrupt the chain.
		app.response = new shelf.Response.ok(null, headers: _createCorsHeader());
		app.chain.interrupt();
	}
	else
	{
    	//process the chain and wrap the response
		app.chain.next(() => app.response.change(headers: _createCorsHeader()));
	}
}

_createCorsHeader() => {"Access-Control-Allow-Origin": "*","Access-Control-Allow-Headers": "Origin, X-Requested-With, Content-Type, Accept"};

@app.Route('/ah/list')
@Encode()
Future<List<Auction>> getAllAuctions() =>
		dbConn.query("select * from auctions", Auction);

@app.Route('/ah/post', methods: const[app.POST])
Future addAuction(@Decode() Auction auction) =>
		dbConn.execute("insert into auctions (item_name,total_cost,username) "
						   "values (@item_name, @total_cost, @username)",auction);

@app.Route('/serverStatus')
Future<Map> getServerStatus() async
{
	Map statusMap = {};
	try
	{
		List<String> users = [];
		ChatHandler.users.forEach((String username, Identifier user)
		{
			if(!users.contains(user.username))
				users.add(user.username);
		});
		statusMap['playerList'] = users;
		statusMap['numStreetsLoaded'] = StreetUpdateHandler.streets.length;
		ProcessResult result = await Process.run("/bin/sh",["getMemoryUsage.sh"]);
		statusMap['bytesUsed'] = int.parse(result.stdout)*1024;
		result = await Process.run("/bin/sh",["getCpuUsage.sh"]);
		statusMap['cpuUsed'] = double.parse(result.stdout.trim());
		result = await Process.run("/bin/sh",["getUptime.sh"]);
        statusMap['uptime'] = result.stdout.trim();
	}
	catch(e){log("Error getting server status: $e");}
	return statusMap;
}

@app.Route('/serverLog')
Future<Map> getServerLog() async
{
	Map statusMap = {};
	try
	{
		DateFormat format = new DateFormat("MM_dd_yy");
		ProcessResult result = await Process.run("tail", ['-n','200','serverLogs/${format.format(startDate)}-server.log']);
		statusMap['serverLog'] = result.stdout;
		return statusMap;
	}
	catch(exception, stacktrace)
	{
		statusMap['serverLog'] = exception.toString();
		return statusMap;
	}
}

@app.Route('/slack', methods: const[app.POST])
String parseMessageFromSlack(@app.Body(app.FORM) Map form)
{
	String username = form['user_name'], text = form['text'];
	if(username != "slackbot" && text != null && text.isNotEmpty)
	{
		Map map = {'username':'dev_$username','message': text,'channel':'Global Chat'};
		ChatHandler.sendAll(JSON.encode(map));
	}

	return "OK";
}

@app.Route('/entityUpload', methods: const[app.POST])
String uploadEntities(@app.Body(app.JSON) Map params)
{
	if(params['tsid'] == null)
		return "FAIL";

	saveStreetData(params);

	return "OK";
}

@app.Route('/getEntities')
Map getEntities(@app.QueryParam('tsid') String tsid)
{
	return getStreetEntities(tsid);
}

@app.Route('/getRandomStreet')
String getRandomStreet() => getTsidOfUnfilledStreet();

@app.Route('/reportStreet')
String reportStreet(@app.QueryParam('tsid') String tsid,
                    @app.QueryParam('reason') String reason,
                    @app.QueryParam('details') String details)
{
	reportBrokenStreet(tsid,reason);

	//post a message to map-filler-reports
	slack.token = mapFillerReportsToken;
    slack.team = slackTeam;

    String text = "$tsid: $reason\n$details";
	slack.Message message = new slack.Message(text,username:"doesn't apply");
	slack.send(message);

	return "OK";
}