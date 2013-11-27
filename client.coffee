UtilsHelper =
  generatePassword: (len)->
    key = ''
    alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-!'
    for i in [1..len]
      key = key + alphabet[Math.ceil(Math.random()*alphabet.length)]
    return key

  storageGet: (key)->
    return $.jStorage.get(key)

  storageSet: (key,value)->
    $.jStorage.set(key,value)
    return true

class CrossWindow
  constructor: ->
    @queue = {}
    @listners = {}
    window.setInterval(
      =>
        @readQueue()
      , 300
    )

  readQueue: =>
    queue = $.parseJSON(@.storageGet("windowQueue"))
    today = new Date()
    nowTimestamp = today.getTime()
    needResave = false
    for taskId,task of queue
      if @queue[taskId]
        delta = nowTimestamp - task.timestamp
        if delta > 4000
          delete queue[taskId]
          needResave = true
        else
          if @listeners[task.event]
            for listner in @listeners[task.event]
              listner.callback(task.data)

    if needResave
      @queue = queue
      @writeQueue()

  writeQueue: =>
    @storageSet("windowQueue",JSON.stringify(@queue))

  on: (eventName,callback)=>
    if !@listeners[eventName]
      @listeners[eventName] = []
    @listeners[eventName].push({"callback":callback})

  emit: (eventName, data = {})=>
    today = new Date()
    task = {"timestamp": today.getTime(),"data": data}
    taskId =  UtilsHelper.generatePassword(5)
    @readQueue()
    @queue[taskId] = task
    writeQueue()
    window.setTimeout(
      =>
        @readQueue()
        delete @queue[taskId]
        writeQueue()
      , 1000
    )

  storageGet: (key)->
    return $.jStorage.get(key)

  storageSet: (key,value)->
    $.jStorage.set(key,value)
    return true


class clientApp
  constructor: ()->
    openpgp.init()
    @socket = io.connect('http://localhost')
    @mainUser = new MainUser(@)
    @usersList = new UserList()
    @connected = ko.observable(false)
    @authStateWord = ko.observable('нет связи')

    @autorizationWord = ko.computed(
      =>
        if(@connected() && @mainUser.statusReady())
          if(!@mainUser.authorized())
            @authStateWord('авторизуемся')
            @authorize()
          else
            @authStateWord('авторизованы')
        else if !@connected()
          @authStateWord('нет связи')
        else if @connected() && !@mainUser.statusReady()
          @authStateWord('генерация ключей')

        return @authStateWord()
    )
    @socket.on 'connect', =>
      console.log('conncted succesfully')
      @connected(true)
    @socket.on 'reconnect', =>
      console.log('conncted succesfully')
      @connected(true)
    @socket.on 'disconnect', =>
      @connected(false)

    @socket.on 'authstep', (data)=>
      if data.cryptPass
        msg = @mainUser.decodeMessage(data.cryptPass)
        if msg
          @socket.emit('authResopnse',{authpass: msg})
        else
          @authStateWord('ошибка авторизации')
    @socket.on 'authorized', (data)=>
      if data.success
        @mainUser.authorized(true)

    @socket.on 'messageFrom', (data)=>
      today = new Date()
      msg = @mainUser.decodeMessage(data.msg)
      if(msg)
        msg = JSON.parse(msg)
        message = new userMessage(false, msg.message, msg.sendTimestamp, today.getTime())
        @usersList.addMessage(data.hash, data.name, message)
      else
        @flashMessage("принятое сообщение невозможно раскодировать")

    @socket.on 'userInfo', (data)=>
      @usersList.addUserInfo data

    @socket.on 'userList', (data)=>
      @usersList.addUserInfo data




      #message.


    ###socket = io.connect('http://localhost')
    @user = new User
    privUniq = $.cookie('privUniq')
    @templateName = ko.observable('loading')
    reqObj = {}
    if privUniq
      reqObj.privateUniq = privUniq
    @onlineUsers = ko.observable(0)
    @memoryUsage = ko.observable(0)
    @updatingUserInfo = ko.observable(false)
    @memoryUsageWord = ko.computed(
      =>
        mem = @memoryUsage()
        kb = Math.floor(mem / 1024)
        return @formatDigit(kb) + ' kb'
    )

    socket.on(
      'userInfo',
      (data)=>
        if @user.privUniq != data.privUniq
          @user.privUniq = data.privUniq
          $.cookie('privUniq',@user.privUniq,{expires:7,path:'/'})
        @user.pubUniq = data.pubUniq
        @updatingUserInfo(true)
        @user.name(data.name)
        #@user.status(data.status)
        @templateName('loaded')
        @updatingUserInfo(false)
    )
    socket.on(
      'userUpdate',
      (data)=>
        @updatingUserInfo(true)
        @user[data.paramName](data.newValue)
        @updatingUserInfo(false)
    )
    @user.name.subscribe(
      (newValue)=>
        if(!@updatingUserInfo())
          socket.emit('userCommand',{'name':'nameChanged','newName':newValue})

    )
    @user.status.subscribe(
      (newValue)=>
        switch newValue
          when 1 then jonToServ()

    )
    socket.emit('init',reqObj)

    socket.on(
      'users',
      (data)=>
        if(data.onlineCount)
          @onlineUsers(data.onlineCount)
        console.log(data)
    )
    socket.on(
      'systemInfo',
      (data)=>
        if(data.memory)
          @memoryUsage(data.memory)
    )###
  joinToServ: =>
    console.log('need join to serv')
    console.log('need join to serv')

  fillServInfo: =>
    console.log('need join to serv')
    console.log('need join to serv')
  flashMessage: (errorMsg,errorType = 0)=>
    # 0 - system error
    if(errorType == 0)
      console.log("system error:"+errorMsg)
    else
      console.log("Error:"+errorMsg)

  authorize: =>
    @socket.emit('init',{pubKey: @mainUser.pubKeyStr})

  unauthorize: =>
    if @mainUser.authorized()
      @socket.emit('unauthorize',true)
      @mainUser.authorized(false)
      @connected(false)
      @connected(true)


  formatDigit: (price) ->
    intPrice = parseInt(price)
    strPrice = intPrice.toString()
    ret = ""
    j = 0
    for i in [(strPrice.length-1)..0]
      if j != 0 && j % 3 == 0
        ret = ' ' + ret
      ret = strPrice[i] + ret
      j++
    return ret

  afterRender: ()=>
    console.log('main div rendered')

class UserList
  constructor: ()->
    @users = ko.observableArray([])
    @usersMap = {}
    @usersIdents = UtilsHelper.storageGet('UsersList')
    @selectedUser = ko.observable(null)
    for md5ident in @usersIdents
      ##user = new User(@)
      userData = UtilsHelper.storageGet('user_'+md5ident)
      if(userData)
        @usersMap[md5ident] = new User(@)
        @usersMap[md5ident].md5ident(md5ident)
        @usersMap[md5ident].pubKeyStr(userData.pubKeyStr)
        @usersMap[md5ident].name(userData.pubKeyStr)
        @usersMap[md5ident].queueMassages = userData.queueMassages
        @users.push(@usersMap[md5ident])

  addUser: (user)=>
    md5ident = user.md5ident()
    if !@usersMap[md5ident]
      @usersMap[md5ident] = user
      @users.push(@usersMap[md5ident])

  addUserInfo: (userInfo)=>
    md5ident = userInfo.hash
    @usersMap[md5ident].pubKeyStr(userInfo.pubKeyStr)


  changeStatus: (md5ident,status)=>
    if @usersMap[md5ident]
      @usersMap[md5ident].status(status)

  addMessage: (md5ident,name,userMessage)=>
    if(!@usersMap[md5ident])
      @usersMap[md5ident] = new User(@)
      @usersMap[md5ident].md5ident(md5ident)
      @usersMap[md5ident].name(name)
      @users.push(@usersMap[md5ident])
    @usersMap[md5ident].messages.push(userMessage)



class User
  constructor: (@userList)->
    @name = ko.observable('')
    @pubKeyStr = ko.observable('')
    @md5ident = ko.observable('')
    @status = ko.observable('offline')
    @messages = ko.observableArray([])
    @pubKey = ko.observable(null)
    @queueMassages = []

class userMessage
  constructor: (@fromYou,@message,@sendTimestamp,@receiptTemestamp = null)->




class MainUser
  constructor: (@app)->
    @name = ko.observable('')
    @name(UtilsHelper.storageGet('username'))
    @statusReady = ko.observable(false)
    @md5ident = ko.observable('')
    @authorized = ko.observable(false)
    @name.subscribe(
      (newValue)=>
        @statusReady(false)
        @app.unauthorize()
        UtilsHelper.storageSet('username',newValue)
    )
    @authProcess = ko.computed =>
      if @name() && !@statusReady()
        window.setTimeout(
          =>
            @generateKeys()
          , 100
        )
      return @name()

    if(@name())
      needGenerate = true
      @pass = UtilsHelper.storageGet('mainpass')
      @pubKeyStr = UtilsHelper.storageGet('mainPubKey')
      privKey = UtilsHelper.storageGet('mainPrivKey')
      if(@pubKeyStr && privKey)
        @pubKey = openpgp.read_publicKey(@pubKeyStr)
        if(!(@pubKey < 1))
          @privKey = openpgp.read_privateKey(privKey)
          @privKey = @privKey[0]
          if(!(@privKey.length < 1))
            needGenerate = false
            @statusReady(true)
            @md5ident(md5(@pubKeyStr))
      if(needGenerate)
        @generateKeys()

  generateKeys: ()=>
    @pass = UtilsHelper.generatePassword((15 + Math.floor(Math.random()*5) ))
    UtilsHelper.storageSet('mainpass',@pass)
    keyPair = openpgp.generate_key_pair(1, 2048, @name(), @pass)
    @pubKeyStr = keyPair.publicKeyArmored
    UtilsHelper.storageSet('mainPubKey',@pubKeyStr)
    UtilsHelper.storageSet('mainPrivKey',keyPair.privateKeyArmored)
    @privKey = keyPair.privateKey
    @pubKey = openpgp.read_publicKey(keyPair.publicKeyArmored)
    @statusReady(true)
    @md5ident(md5(@pubKeyStr))

  decodeMessage: (messageStr)=>
    msg = openpgp.read_message(messageStr);
    keymat = null;
    sesskey = null;
    #Find the private (sub)key for the session key of the message
    for sessionKey in msg[0].sessionKeys
      sessionKey
      if @privKey.privateKeyPacket.publicKey.getKeyId() == sessionKey.keyId.bytes
        keymat = { key: @privKey, keymaterial: @privKey.privateKeyPacket}
        break
      for subKey in @privKey.subKeys
        if subKey.publicKey.getKeyId() == sessionKey.keyId.bytes
          keymat = {key: @privKey, keymaterial: subKey}
          break
    if keymat != null
      if !keymat.keymaterial.decryptSecretMPIs(@pass)
        return false
      return msg[0].decrypt(keymat,sessionKey)
    else return false


cApp = new clientApp()
window.uttt = 1234
window.UtilsHelper = UtilsHelper

$(document).ready(
  ->
    console.log('ko bind')
    ko.applyBindings(cApp);
    window.cApp = cApp
    return true
)
