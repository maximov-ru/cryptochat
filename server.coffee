helper =
  testString: (str, maxLen, regReplace)->
    if typeof str == 'string'
      if str.length <= maxLen
        str = str.replace(/\s+/,' ')
        str = str.trim()
        str = str.replace(/[^a-zA-Zа-яА-ЯёЁ0-9 ]/g,'')
        return str
    return false

  genAlphabet: 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-!'
  generatePassword: (len)->
    key = ''
    alphabet = helper.genAlphabet
    for i in [1..len]
      key = key + alphabet[Math.ceil(Math.random()*alphabet.length)]
    return key

  baseAlpha: ['bfnsJwMZNSruVPBFjLmQWeEaHtzCAxhdcXkDYGpKUyTRv','dwVxjRPJFNYhDbumHyveGTWQkcsazXCBfMrASKnUEZptL','XQaRjszLWxYNEekubPvHKDdSnTphMAVBcFmZGtywJrfUC'],

  intToStr: (int, baseId)=>
    len = helper.baseAlpha[baseId].length
    ret = ''
    while int > (len - 1)
      ret = helper.baseAlpha[baseId][(int % len)] + ret
      int = Math.floor( int / len)
    return helper.baseAlpha[baseId][(int)] + ret

  strToInt: (str, baseId)=>
    len = helper.baseAlpha[baseId].length
    size = str.length - 1
    ret = 0
    for i in [0..size]
      ret += helper.baseAlpha[baseId].indexOf(str[(size-i)]) * Math.pow(len,i)
    return ret



UserManager =
  ### @myserv serv  ###
  myServ: null,
  newUser: ()->
    user = new User()
    return user

  setParam: (user,paramName,val)=>
    user[paramName] = val
    UserManager.myServ.db.set(
      ('user_'+paramName+user.privUniq),
      val
    )

  updateUserParam: (user,socket,paramName)->
    socket.emit('userUpdate',{paramName: paramName,newValue:user[paramName]})

  nameChanged: (user,socket,newName)->
    newNameFiltered = helper.testString(newName,30)
    if newNameFiltered
      UserManager.setParam(user,'name',newNameFiltered)
    else
      console.log('name filetered',newName,newNameFiltered)
    if(newNameFiltered != newName)
      UserManager.updateUserParam(user,socket,'name')
    for socketId,sock of user.connections
      if(socketId != socket.id)
        UserManager.updateUserParam(user,sock,'name')

    #send to all subscribed objects

  sendUserInfo: (user,socket)=>
    console.log('send userInfo')
    userObj = {}
    userObj.name = user.name
    userObj.privUniq = user.privUniq
    userObj.pubUniq = user.pubUniq
    socket.emit('userInfo',userObj)

  getUserInfo: (userPub)=>
    userObj = {}
    userObj.pubUniq = userPub
    if UserManager.myServ.connectedPublicUsersMap[userPub]
      userObj.name = UserManager.myServ.connectedPublicUsersMap[userPub].name
    return userObj

  connectionPush: (user,socket)->
    user.connections[socket.id] = socket
    user.connectionsCount++
    if user.connectionsCount == 1
      UserManager.myServ.usersUpdated(1)
    socket.on(
      'userCommand',
      (command)->
        UserManager.parseCommand(user,socket,command)
    )
    socket.on(
      'disconnect',
      ->
        UserManager.connectionPop(user,socket)
        if user.connectionsCount == 0
          UserManager.myServ.usersUpdated(-1)
          if user.pubUniq
            delete UserManager.myServ.connectedPublicUsersMap[user.pubUniq]
          delete UserManager.myServ.connectedUsers[user.privUniq]
    )

  connectionPop: (user,socket)->
    delete user.connections[socket.id]
    user.connectionsCount--


  parseCommand: (user,socket,command)->
    if command.name
      switch command.name
        when "nameChanged" then UserManager.nameChanged(user,socket,command.newName)



  createUser: (user,socket,newUniq)->
    console.log('createUser')
    UserManager.connectionPush(user,socket)
    user.privUniq = newUniq
    UserManager.setParam(user,'pubUniq',UserManager.myServ.getPubUniq())
    UserManager.setParam(user,'name',UserManager.myServ.getNewName())
    user.filled = true
    UserManager.myServ.connectedPublicUsersMap[user.pubUniq] = UserManager.myServ.connectedUsers[user.privUniq]
    UserManager.sendUserInfo(user,socket)
    UserManager.myServ.usersUpdated(1)

  addConnection: (user,socket)->
    console.log('addConection')
    UserManager.connectionPush(user,socket)
    UserManager.fillUser(
      user,
      socket,
      (user,socket)->
        console.log('sendUser callback')
        UserManager.sendUserInfo(user,socket)
    )

  fillUser: (user,socket,callback)->
    if ((!user.filled) && (!user.filling))
      console.log('filling user')
      initParams = ['pubUniq','name','state','servChain']
      n = initParams.length-1;
      if user.privUniq
        reqKeys = []
        user.filling = true
        for param in initParams
          reqKeys.push('user_'+param+user.privUniq)
        UserManager.myServ.db.mget(
          reqKeys,
          (err,ret)=>
            for i in [0..n]
              user[initParams[i]] = ret[i]
            user.filled = true
            user.filling = false

            UserManager.myServ.connectedPublicUsersMap[user.pubUniq] = UserManager.myServ.connectedUsers[user.privUniq]
            callback(user,socket)
        )
      else
        console.log('user object empty',user)
    else
      callback(user,socket)



class User
  pubUniq: '',
  privUniq: '',
  filled: false,
  filling: false,
  name: '',
  state: 1,
  servChain: '',
  connections: {},
  connectionsCount: 0

class UserReg
  name: '',
  pass: '',
  statistic: '',

class ChainServ
  name: '',
  uniq: '',
  users: {},
  usercCount: 0,
  state: 1,
  userOwner: '',

class serv
  constructor: ->
    @app = require('http').createServer(@mainHandler)
    @io = require('socket.io').listen(@app)
    @io.set('log level', 1)
    @fs = require('fs')
    @openpgp = require('./modules/openpgp_serv.js')
    @openpgp.openpgp.init()
    #console.log(@openpgp.md5("123"))
    #process.exit()
    @users = {count: 0}
    @app.listen(8080)
    @io.sockets.on('connection', @userConnection)
    @io.sockets.on 'disconnect', (socket)=>
      delete @connectionsData[socket.id]

    @redis = require('redis')
    UserManager.myServ = @
    @db = @redis.createClient(6379, 'localhost');
    initParams = ['userNum','userPrivNum','servNum']
    for param in initParams
      @db.get(
        param,
        (err,reply)=>
          @[param] = reply
      )

    setInterval(
      =>
        @systemUpdated()
      , 15000
    )

  onlineUsers: 0,
  connectedUsers: {},
  connectedPublicUsersMap: {},
  connectionsData: {},#state 0 - uninited, state 1 inited and wating respons for question, state 2 - connected
  gameChains: {},
  onlineUsersUpdating: false,
  systemInfo: {},
  namesCount: {}
  usersUpdated: (delta)=>
    @onlineUsers += delta
    if !@onlineUsersUpdating
      console.log('send users count',@onlineUsers)
      @io.sockets.emit( 'users', {onlineCount: @onlineUsers} )
      @onlineUsersUpdating = @onlineUsers
      setTimeout(
        =>
          tmp = @onlineUsersUpdating
          @onlineUsersUpdating = false
          if tmp != @onlineUsers
            @usersUpdated(0)
        , 5000
      )

  #running every 15 secs
  systemUpdated: ()=>
    @systemInfo.memory = process.memoryUsage().heapTotal
    @io.sockets.emit( 'systemInfo', @systemInfo )

  paramInc: (paramName)=>
    if typeof @[paramName] != 'undefined'
      @[paramName]++
      @db.set(paramName, @[paramName])
    return @[paramName];
  userNum: 0,
  userPrivNum: 0,
  servNum: 0,
  getPubUniq: =>
    return helper.intToStr(@paramInc('userNum'),1)

  getChainUniq: =>
    return helper.intToStr(@paramInc('servNum'),2)
    
  getPrivUniq: =>
    @userPrivNum += 1+Math.floor(Math.random()*50)
    return helper.intToStr(@paramInc('userPrivNum'),0)

  getNewName: =>
    names = ['user','gamer','player']
    nameWord = names[Math.floor(Math.random()*names.length)]
    if(!@namesCount[nameWord])
      @namesCount[nameWord] = 1
    else
      @namesCount[nameWord]++
    return nameWord+@namesCount[nameWord]

  setUser: (socket, data)=>
    console.log('userAuthorized',data)
    return true
    if data.privateUniq
      if @connectedUsers[data.privateUniq]
        console.log('nashel v operativke')
        UserManager.addConnection(@connectedUsers[data.privateUniq],socket)
      else
        console.log('ishu v redis')
        @connectedUsers[data.privateUniq] = new User()
        @db.get(
          'user_privUniq'+data.privateUniq,
          (err,ret)=>
            if err
              console.log('netu v redis')
              newUniq = @getPrivUniq()
              delete @connectedUsers[data.privateUniq]
              @connectedUsers[newUniq] = new User()
              UserManager.createUser(@connectedUsers[newUniq],socket,newUniq)
            else
              console.log('nashel v redis')
              @connectedUsers[data.privateUniq].privUniq = data.privateUniq
              UserManager.addConnection(@connectedUsers[data.privateUniq],socket)
        )
    else
      console.log('noviy user')
      newUniq = @getPrivUniq()
      @connectedUsers[newUniq] = new User()
      UserManager.createUser(@connectedUsers[newUniq],socket,newUniq)

  mainHandler: (req, res)=>
    console.log(req.url)
    urls = {'/index.html':'/index.html','/':'/index.html','/client.js':'/client.js'}
    urls['/templates/user-info.html'] = '/templates/user-info.html'
    urls['/templates/loaded.html'] = '/templates/loaded.html'
    urls['/templates/loading.html'] = '/templates/loading.html'
    urls['/js/knockout-min.js'] = '/js/knockout-min.js'
    urls['/js/jquery.min.js'] = '/js/jquery.min.js'
    urls['/js/jstorage.js'] = '/js/jstorage.js'
    urls['/js/mouse.js'] = '/js/mouse.js'
    urls['/js/openpgp.js'] = '/js/openpgp.js'
    urls['/js/jquery.js'] = '/js/jquery.js'
    urls['/js/bootstrap.min.js'] = '/js/bootstrap.min.js'
    if urls[req.url]
      @fs.readFile(
        __dirname + urls[req.url],
        (err, data)->
          if err
            res.writeHead(500)
            return res.end('Error loading file')
          res.writeHead(200)
          res.end(data)
      )

  unauthorized: (socket,reason)=>
    socket.emit('unauthorized',{"reason":reason})
    @connectionsData[socket.id] = {question:"",state:0}

  userConnection: (socket)=>
    console.log('new user')
    @connectionsData[socket.id] = {question:"",state:0}
    socket.on(
      'init',
      (data)=>
        if @connectionsData[socket.id]["state"] == 0
          if data.pubKey
            @connectionsData[socket.id]["pubKeyStr"] = data.pubKey
            pubKey = @openpgp.openpgp.read_publicKey(data.pubKey)
            @connectionsData[socket.id]["pubKey"] = pubKey
            if pubKey < 1
              @unauthorized(socket,"pubKey not correct")
            else
              @connectionsData[socket.id]["authpass"] = helper.generatePassword(10)
              cryptPass = @openpgp.openpgp.write_encrypted_message(pubKey,@connectionsData[socket.id]["authpass"])
              @connectionsData[socket.id]["state"] = 1
              socket.emit('authstep',{"cryptPass": cryptPass})
          else
            @unauthorized(socket,"pubKey not found")
    )
    socket.on(
      'authResopnse',
      (data)=>
        if @connectionsData[socket.id]["state"] == 1
          if data.authpass
            if @connectionsData[socket.id]["authpass"] == data.authpass
              @connectionsData[socket.id]["state"] = 2
              socket.emit('authorized',{"success": true})
              delete @connectionsData[socket.id]["authpass"]
              authData = {}
              authData["name"] = @connectionsData[socket.id]["pubKey"][0].userIds[0].text
              authData["pubKeyStr"] = @connectionsData[socket.id]["pubKeyStr"]
              authData["md5"] = @openpgp.md5(authData["name"] + authData["pubKeyStr"])
              @setUser(socket,authData)
          else
            @unauthorized(socket,"authpass not defined")
    )
    #@usersUpdated(1)

    ###socket.on(
      'disconnect',
      ()=>
        console.log('user disconnect')
        @usersUpdated(-1)
    )###


myServ = new serv()
