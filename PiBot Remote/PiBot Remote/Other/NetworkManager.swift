//
//  networkManager.swift
//  PiBot Remote
//
//  Created by Robert Swanson on 2/26/18.
//  Copyright © 2018 Robert Swanson. All rights reserved.
//

import UIKit
import Foundation
import NMSSH

protocol NetworkManagerDelegate: class{
	func receivedMessage(message: Message)
}

class NetworkManager: NSObject {
	weak var delegate: NetworkManagerDelegate?
	var tabBar: TabBarController!
	var inputStream: InputStream!
	var outputStream: OutputStream!
	
	var session: NMSSHSession?
	
	let maxReadLength = 1024
	var ping = false
	var startClientSwitch = true
	
	private let sendDelay = 0.1
	private var pendingInstructions: [Message] = []
	private var indexOfMoveInstruction = -1
	private var sendingInstruc = false
	
	public var lastMovementInstruc: [CGFloat] = [0.0,0.0]
	
	let settings = UserDefaults.standard
	
	public func getAddress() -> String{
		var address: String = "pibot.local"
		if let val = UserDefaults.standard.value(forKey: SettingsViewController.setting.hostName.toString()) as? String{
			address = val
		}else{
			UserDefaults.standard.set(address, forKey: SettingsViewController.setting.hostName.toString())
		}
		return address
	}
	public func getUsername() -> String{
		var username: String = "pi"
		if let val = UserDefaults.standard.value(forKey: SettingsViewController.setting.username.toString()) as? String{
			username = val
		}else{
			UserDefaults.standard.set(username, forKey: SettingsViewController.setting.username.toString())
		}
		return username
	}
	
	public func getPassword() -> String{
		var password: String = "example"
		if let val = UserDefaults.standard.value(forKey: SettingsViewController.setting.password.toString()) as? String{
			password = val
		}else{
			UserDefaults.standard.set(password, forKey: SettingsViewController.setting.password.toString())
		}
		return password
	}
	public func getPort() -> UInt32{
		var port: UInt32 = 2001
		if let val = UserDefaults.standard.value(forKey: SettingsViewController.setting.port.toString()) as? String?{
			port = UInt32(val!)!
		}else{
			UserDefaults.standard.set("2001", forKey: SettingsViewController.setting.port.toString())
		}
		
		return port
	}
	public func getAutoStartSSH() -> Bool{
		if let val = UserDefaults.standard.value(forKey: SettingsViewController.setting.autoStartClient.toString()) as? Bool{
			startClientSwitch = val
		}else{
			UserDefaults.standard.set(startClientSwitch, forKey: SettingsViewController.setting.autoStartClient.toString())
		}
		return startClientSwitch
	}
	func TCPConnected() -> Bool{
		return inputStream != nil && outputStream != nil
	}
	func SSHConnected() -> Bool{
		return session != nil && (session?.isConnected)! && (session?.isAuthorized)!
	}
	
	@objc func setupConnection(){
		Thread(target: tabBar, selector: #selector(tabBar.showActivityIndicator), object: nil).start()
		if let val = UserDefaults.standard.value(forKey: SettingsViewController.setting.client.toString()) as? Bool{
			startClientSwitch = val
		}
		Console.log(text: "Connecting to: \(getAddress()) at port: \(getPort())...", level: .basic)
		if(!startClientSwitch){
			Console.log(text: "Not Starting Client as set in settings", level: .advanced)
		}
		if(!getAutoStartSSH() || startClient()){
			var readStream: Unmanaged<CFReadStream>?
			var writeStream: Unmanaged<CFWriteStream>?
			
			CFStreamCreatePairWithSocketToHost(kCFAllocatorDefault, getAddress() as CFString, getPort(), &readStream, &writeStream)
			
			inputStream = readStream!.takeRetainedValue()
			outputStream = writeStream!.takeRetainedValue()
			
			inputStream.delegate = self as StreamDelegate
			outputStream.delegate = self as StreamDelegate
			
			inputStream.schedule(in: .main, forMode: .commonModes)
			outputStream.schedule(in: .main, forMode: .commonModes)
			
			inputStream.open()
			outputStream.open()
			ping(timeout: 5.0)
		}
	}
	
	private func setupSSH() -> Bool{
		Console.log(text: "Setting up SSH", level: .advanced)
		if(session == nil){
			session = NMSSHSession(host: getAddress(), andUsername: getUsername())
		}
		if(!(session?.isConnected)! && !(session?.connect())!){
			Console.log(text: "Connection Failed because a SSH connection could not be established to \(getAddress()). Make sure the robot is powered on and is on the same network as this device.", level: .basic)
			tabBar.updateConnectedIcons(to: false)
			tabBar.displayFailedConnectionAlert()
			return false
		}
		if(!(session?.isAuthorized)!){
		session?.authenticate(byPassword: getPassword())
			if(!(session?.isAuthorized)!){
				session?.disconnect()
				Console.log(text: "SSH authentication failed, make sure \(getPassword()) is the correct password", level: .basic)
				tabBar.updateConnectedIcons(to: false)
				tabBar.displayFailedConnectionAlert()
				return false
			}
		}
		return true
	}
	
	private func startClient() -> Bool{
		if(!setupSSH()){
			return false
		}
		Thread(target: self, selector: #selector(clientThread), object: nil).start()
		usleep(1000000)
		return true
	}
	
	public func sendSSHCommand(command: String, progressBar: UIProgressView?) -> String{
		let tempSess = NMSSHSession(host: getAddress(), andUsername: getUsername())
		tempSess?.connect()
		if(tempSess?.isConnected)!{
			tempSess?.authenticate(byPassword: getPassword())
			if(tempSess?.isAuthorized)!{
				do {
					var rv = ""
					Console.log(text: "Executing SSH Command: \(command)", level: .advanced)
					try	rv = (tempSess?.channel.execute(command))!
					if(rv.count != 0){
						Console.log(text: "SSH OUTPUT:\n \(rv)", level: .advanced)
					}
					Console.log(text: "SSH Output: \(rv)", level: .debug)
					return rv
				} catch {
					Console.log(text: error as! String, level: .advanced)
				}
			}else{
				Console.log(text: "SSH COMMAND ERRROR: Could not authenticate, check to make the password is correct", level: .basic)
			}
		}else{
			Console.log(text: "SSH COMMAND ERRROR: Could not connect, check to make sure the address and username are correct", level: .basic)
		}
		return ""
	}
	
	@objc private func clientThread(){
		do {
			let command = "python /home/pi/Desktop/PiBotRemoteFiles/server.py \(getPort()) \(getPinSettingString())"
			Console.log(text: command, level: .debug)
			Console.log(text: "Starting Client", level: .advanced)
			try	Console.log(text: "---------Pi Output---------\n\((session?.channel.execute(command))!)---------------------------",level: .debug)
		} catch {
			Console.log(text: "Client thread error: c\(error)", level: .advanced)
		}
		if TCPConnected(){
			closeTCP()
		}
	}
	
	func send(message: Message){
		if((message.type == .move || message.type == .servo) && indexOfMoveInstruction != -1){
			pendingInstructions.remove(at: indexOfMoveInstruction)
			indexOfMoveInstruction = pendingInstructions.count
			print("Removed Previous Instruc")
		}else if(message.type == .move || message.type == .servo){
			indexOfMoveInstruction = pendingInstructions.count
		}
		pendingInstructions.append(message)
		if(!sendingInstruc){
			sendingInstruc = true
			sheduleLoop(delay: 0)
		}
	}
	
	@objc private func instrucLoop(){
		if(lastMovementInstruc == [0.0,0.0]){
			while(!pendingInstructions.isEmpty && pendingInstructions.first!.type == Message.MessType.move && pendingInstructions.first!.values == [0.0,0.0]){
				pendingInstructions.removeFirst()
				if(indexOfMoveInstruction != -1){
					indexOfMoveInstruction -= 1
				}
			}
		}
		if(!pendingInstructions.isEmpty){
			sendInstruc(message: pendingInstructions.first!)
			if(pendingInstructions.first!.type == Message.MessType.move){
				lastMovementInstruc = (pendingInstructions.first!.values!)
			}
			if(indexOfMoveInstruction != -1){
				indexOfMoveInstruction -= 1
			}
			pendingInstructions.removeFirst()
		}
		sendingInstruc = !pendingInstructions.isEmpty
		if(sendingInstruc){
			sheduleLoop(delay: sendDelay)
		}
	}
	
	private func sheduleLoop(delay:Double){
		let _ = Timer.scheduledTimer(timeInterval: delay, target: self, selector: #selector(instrucLoop), userInfo: nil, repeats: false)
	}
	
	private func sendInstruc(message: Message){
		print("instruc finally sent")
		if(message.type != Message.MessType.move && message.type != Message.MessType.servo && message.type != Message.MessType.stop){
			Console.log(text: "SENDING MESSAGE: \(message.toString())", level: .debug)
		}
		if(TCPConnected()){
			var data = (message.toString().trimmingCharacters(in: .whitespaces)+"$").data(using: .ascii)!
			if(data.isEmpty || message.toString() == ""){
				return
			}
			_ = data.withUnsafeBytes { outputStream.write($0, maxLength: data.count)}
		}
	}
	
	func ping(timeout: Double){
		if(ping){
			return
		}
		ping = true
		send(message: Message(type: .ping))
		let _ = Timer.scheduledTimer(timeInterval: timeout, target: self, selector: #selector(checkPing), userInfo: nil, repeats: false)
	}
	
	@objc func checkPing(){
		if ping{
			Console.log(text: "Connection failed because the client did not acknowledge the connection. This likely means there is an error in the client code on the robot.", level: .basic)
			closeTCP()
			tabBar.displayFailedConnectionAlert()
			tabBar.updateConnectedIcons(to: false)
		}
	}
	
	func closeTCP(){
		Thread(target: tabBar, selector: #selector(tabBar.showActivityIndicator), object: nil).start()
		ping = true
		send(message: Message(type: .close))
		let start = Date().millisecondsSince1970
		while ping && Date().millisecondsSince1970 - start < 1000{}
		if ping{
			ping = false
		}
		if(inputStream != nil){
			inputStream.close()
			inputStream = nil
		}
		if(outputStream != nil){
			outputStream.close()
			outputStream = nil
		}
		Console.log(text: "TCP Disconnected", level: .basic)
		tabBar.updateConnectedIcons(to: false)
	}
	
	func closeSSH(){
		if(SSHConnected()){
			session?.disconnect()
		}
	}
	
	func getSet(set: SettingsViewController.setting.Pin, def: Int) -> Int{
		if let val = settings.value(forKey: set.toString()) as? Int{
			return val
		}else{
			settings.set(def, forKey: set.toString())
			return def
		}
	}
	
	public func getPinSettingString() -> String{
		var rv = ""
		rv += String(getSet(set: SettingsViewController.setting.Pin.PWMA, def: 7)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.AIN1, def: 12)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.AIN2, def: 11)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.STBY, def: 13)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.BIN1, def: 15)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.BIN2, def: 16)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.PWMB, def: 18)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.SERVO, def: 22)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.connected, def: 37)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.replaying, def: 38)) + " "
		rv += String(getSet(set: SettingsViewController.setting.Pin.data, def: 40))
		return rv
	}
}
extension NetworkManager: StreamDelegate {
	func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		switch eventCode {
		case Stream.Event.hasBytesAvailable:
			readAvailableBytes(stream: aStream as! InputStream)
		case Stream.Event.endEncountered:
			Console.log(text: "Closing Connection", level: .debug)
			closeTCP()
		case Stream.Event.errorOccurred:
			Console.log(text: "ERROR: "+String(describing: eventCode), level: .advanced)
			closeTCP()
			Console.log(text: "Connection failed because TCP connection could not be made to \(getAddress()) on port \(getPort())", level: .basic)
			tabBar.displayFailedConnectionAlert()
//		case Stream.Event.hasSpaceAvailable:
//			tabBar.console(mess: "has space available")
		default:
//			tabBar.console(mess: "some other event")
			break
		}
	}
	
	private func readAvailableBytes(stream: InputStream) {
		let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: maxReadLength)
		
		while stream.hasBytesAvailable {
			let numberOfBytesRead = inputStream.read(buffer, maxLength: maxReadLength)
			
			if numberOfBytesRead < 0 {
				if let _ = inputStream.streamError {
					break
				}
			}
			
			if let message = processedMessageString(buffer: buffer, length: numberOfBytesRead) {
				delegate?.receivedMessage(message: message)
			}else{
				Console.log(text: "Unable to read message", level: .debug)
			}
		}
	}
	
	private func processedMessageString(buffer: UnsafeMutablePointer<UInt8>,length: Int) -> Message? {
		let message = String(bytesNoCopy: buffer,length: length,encoding: .ascii,freeWhenDone: true)
		return Message(messageString: message!)
	}
}

extension Date {
	var millisecondsSince1970:Int {
		return Int((self.timeIntervalSince1970 * 1000.0).rounded())
	}
	
	init(milliseconds:Int) {
		self = Date(timeIntervalSince1970: TimeInterval(milliseconds / 1000))
	}
}
