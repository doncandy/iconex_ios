//
//  WalletManager.swift
//  iconex_ios
//
//  Copyright © 2018 ICON Foundation. All rights reserved.
//

import Foundation
import ICONKit
import BigInt
import Result
import Realm
import RealmSwift

typealias WalletBundleItem = (name: String, privKey: String, address: String, type: COINTYPE)

class Preference {
    private init() {}
    
    static let shared = Preference()
    
    var navSelected: Int = 0
}

class WalletManager {
    
    static let sharedInstance = WalletManager()
    
    public var service: ICONService {
        switch Config.host {
        case .main:
            return ICONService(provider: "https://wallet.icon.foundation", nid: "0x1")
            
        case .dev:
            return ICONService(provider: "https://testwallet.icon.foundation", nid: "0x2")
            
        case .yeouido:
            return ICONService(provider: "https://bicon.net.solidwallet.io", nid: "0x3")
        }
    }
    
    var walletInfoList = [WalletInfo]()
    
    private var govnAddress = "cx0000000000000000000000000000000000000001"
    
    private init () {
        loadWalletList()
        DB.importLocalTokenList()
    }
    var countOfWalletType: Int {
        return DB.walletTypes().count
    }
    
    let userPath = ""
    
    func loadWalletList() {
        walletInfoList.removeAll()
        do {
            let realm = try Realm()
            
            let list = realm.objects(WalletModel.self).sorted(byKeyPath: "createdDate").reversed()
            
            for walletModel in list {
                
                let wallet = WalletInfo(model: walletModel)
                
                walletInfoList.append(wallet)
                
            }
            
        } catch {
            Log.Debug("Get wallet list Error: \(error)")
        }
    }
    
    func loadWalletBy(info: WalletInfo) -> BaseWalletConvertible? {
        guard var wallet = DB.walletBy(info: info) else { return nil }
        wallet.balance = Balance.walletBalanceList[info.type == .eth ? info.address.add0xPrefix() : info.address]
        return wallet
    }
    
    func loadWalletBy(address: String, type: COINTYPE) -> BaseWalletConvertible? {
        guard var wallet = DB.walletBy(address: address.lowercased(), type: type) else { return nil }
        wallet.balance = Balance.walletBalanceList[type == .eth ? address.add0xPrefix() : address]
        return wallet
    }
    
    private func getWalletInfo(alias: String) throws -> Data {
        var path = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        path = path.appendingPathComponent(alias)
        return try Data(contentsOf: path)
    }
    
    func getStepCosts() -> ICONKit.Response.StepCosts? {
        let call = Call<ICONKit.Response.Call<ICONKit.Response.StepCosts>>(from: "hx0000000000000000000000000000000000000000", to: self.govnAddress, method: "getStepCosts", params: nil)
        let result = self.service.call(call).execute()
        
        guard let value = result.value, let cost = value.result else {
            Log.Debug("error - \(String(describing: result.error))")
            return nil }
        Log.Debug("cost - \(cost)")
        return cost
    }
    
    func getMaxStepLimit() -> BigUInt? {
        let call = Call<ICONKit.Response.Call<String>>(from: "hx0000000000000000000000000000000000000000", to: self.govnAddress, method: "getMaxStepLimit", params: ["contextType": "invoke"])
        let result: Result = self.service.call(call).execute()
        
        guard let value = result.value, let max = value.result, let maxLimit = BigUInt(max.prefix0xRemoved(), radix: 16) else { return nil }
        Log.Debug("max - \(maxLimit)")
        return maxLimit
    }
    
    func getMinStepLimit() -> BigUInt? {
        let call = Call<ICONKit.Response.Call<String>>(from: "hx0000000000000000000000000000000000000000", to: self.govnAddress, method: "getMinStepLimit", params: nil)
        let result = self.service.call(call).execute()
        
        guard let value = result.value, let min = value.result, let minLimit = BigUInt(min.prefix0xRemoved(), radix: 16) else { return nil }
        Log.Debug("min - \(minLimit)")
        return minLimit
    }
    
    func getStepPrice() -> BigUInt? {
        let call = Call<ICONKit.Response.Call<String>>(from: "hx0000000000000000000000000000000000000000", to: self.govnAddress, method: "getStepPrice", params: nil)
        let result = self.service.call(call).execute()
        
        guard let value = result.value, let stringPrice = value.result, let stepPrice = BigUInt(stringPrice.prefix0xRemoved(), radix: 16) else { return nil }
        Log.Debug("stepPrice - \(stepPrice)")
        return stepPrice
    }
    
    func canSaveWallet(alias: String) -> Bool {
        let realm = try! Realm()
        
        let list = realm.objects(WalletModel.self).filter { $0.name == alias }
        
        if list.count > 0 {
            return false
        }
        
        return true
    }
    
    func canSaveWallet(address: String) -> Bool {
        let realm = try! Realm()
        
        let wallet = realm.objects(WalletModel.self).filter( { $0.address.lowercased() == address.lowercased() })
        if wallet.count > 0 {
            return false
        }
        
        return true
    }
    
    func changeWalletName(former: String, newName: String) throws -> Bool {
        return try DB.changeWalletName(former: former, newName:newName)
    }
    
    func changeWalletPassword(wallet: BaseWalletConvertible, old: String, new: String) throws -> Bool {
        return try DB.changeWalletPassword(wallet: wallet, oldPassword: old, newPassword: new)
    }
    
    @discardableResult
    func deleteWallet(wallet: BaseWalletConvertible) -> Bool {
        do {
            let result = try DB.deleteWallet(wallet: wallet)
            
            WManager.loadWalletList()
            
            return result
        } catch {
            Log.Debug("\(error)")
            return false
        }
    }
    
    func walletTypes() -> [String] {
        return DB.walletTypes()
    }
    
    func tokenTypes() -> [TokenInfo] {
        return DB.allTokenList()
    }
    
    func coinInfoListBy(coin: COINTYPE) -> CoinInfo? {
        return DB.walletListBy(coin: coin)
    }
    
    func coinInfoListBy(token: TokenInfo) -> CoinInfo? {
        return DB.walletListBy(token: token)
    }
}

extension WalletManager {
    public func sendICX(privateKey: PrivateKey, from: String, to: String, value: BigUInt, stepLimit: BigUInt, message: String? = nil) -> Result<ICONKit.Response.TxHash, ICONResult> {
        let transaction = Transaction()
            .from(from)
            .to(to)
            .value(value)
            .stepLimit(stepLimit)
            .nonce("0x1")
            .nid(self.service.nid)
        
        if let msg = message {
            transaction.message(msg)
        }
        
        guard let signedTransaction = try? SignedTransaction(transaction: transaction, privateKey: privateKey) else {
            return .failure(ICONResult.sign)
        }
        
        return self.service.sendTransaction(signedTransaction: signedTransaction).execute()
    }
    
    public func sendIRCToken(privateKey: PrivateKey, from: String, to: String, contractAddress: String, value: BigUInt, stepLimit: BigUInt) -> Result<ICONKit.Response.TxHash, ICONResult> {
        let transaction = Transaction()
        transaction.from(from)
            .to(contractAddress)
            .stepLimit(stepLimit)
            .nid(self.service.nid)
            .nonce("0x1")
            .call("transfer")
            .params(["_to": to, "_value": "0x" + String(value, radix: 16)])
        
        guard let signed = try? SignedTransaction(transaction: transaction, privateKey: privateKey) else {
            return .failure(ICONResult.sign)
        }
        return self.service.sendTransaction(signedTransaction: signed).execute()
    }
    
    public func getIRCTokenInfo(walletAddress: String, contractAddress: String, completion: @escaping (((name: String, symbol: String, decimal: String)?) -> ())) {
        
        DispatchQueue.global().async {
            let nameCall = Call<ICONKit.Response.Call<String>>(from: walletAddress, to: contractAddress, method: "name", params: nil)
            let result = self.service.call(nameCall).execute()
            
            guard let nameResponse = result.value, let name = nameResponse.result else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            Log.Debug("name - \(name)")
            
            let decimalCall = Call<ICONKit.Response.Call<String>>(from: walletAddress, to: contractAddress, method: "decimals", params: nil)
            let decResult = self.service.call(decimalCall).execute()
            
            guard let decResponse = decResult.value, let decimal = decResponse.result else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            Log.Debug("decimal - \(decimal)")
            
            let symCall = Call<ICONKit.Response.Call<String>>(from: walletAddress, to: contractAddress, method: "symbol", params: nil)
            let symResult = self.service.call(symCall).execute()
            
            guard let symResponse = symResult.value, let symbol = symResponse.result else {
                DispatchQueue.main.async {
                    completion(nil)
                }
                return
            }
            Log.Debug("symbol - \(symbol)")
            
            DispatchQueue.main.async {
                completion((name: name, symbol: symbol, decimal: decimal))
            }
        }
    }
    
    public func getIRCTokenBalance(tokenInfo: TokenInfo) -> BigUInt? {
        let service = WManager.service
        
        let call = Call<ICONKit.Response.Call<String>>(from: tokenInfo.dependedAddress, to: tokenInfo.contractAddress, method: "balanceOf", params: ["_owner": tokenInfo.dependedAddress])
        let result = service.call(call).execute()
        
        guard let value = result.value, let balance = value.result else { return nil }
        
        return BigUInt(balance.prefix0xRemoved(), radix: 16)
    }
    
    public func getIRCTokenBalance(dependedAddress: String, contractAddress: String) -> Result<ICONKit.Response.Call<String>, ICONResult> {
        let service = WManager.service
        
        let call = Call<ICONKit.Response.Call<String>>(from: dependedAddress, to: contractAddress, method: "balanceOf", params: ["_owner": dependedAddress])
        let result = service.call(call).execute()
        
        return result
    }
    
}

let WManager = WalletManager.sharedInstance
