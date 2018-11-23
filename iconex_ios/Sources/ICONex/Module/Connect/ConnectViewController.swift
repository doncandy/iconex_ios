//
//  ConnectViewController.swift
//  iconex_ios
//
//  Copyright © 2018 ICON Foundation. All rights reserved.
//

import UIKit
import RxSwift
import BigInt

class ConnectViewController: BaseViewController {
    @IBOutlet weak var refresh01: UIImageView!
    @IBOutlet weak var refresh02: UIImageView!
    
    var didProceed: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        
        balanceListDidChanged().observeOn(MainScheduler.instance).subscribe(onNext: { [weak self] _ in
            if Conn.isTranslated {
                self?.proceed()
            }
        }).disposed(by: disposeBag)
        
        
        Tools.rotateAnimation(inView: refresh01)
        Tools.rotateReverseAnimation(inView: refresh02)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if Conn.needTranslate {
            do {
                try Conn.translate()
                proceed()
            } catch let e as ConnectError {
                Log.Debug("ConnectError - \(e)")
                Conn.sendError(error: e)
            } catch {
                Log.Debug("error - \(error)")
                Conn.sendError(error: .invalidRequest)
            }
        }
    }
    
    func proceed() {
        if !didProceed{
            if prepare() {
                action()
            }
        }
    }
    
    func prepare() -> Bool {
        if Conn.action == "bind" {
            guard WManager.walletInfoList.count > 0 else {
                Conn.sendError(error: .walletEmpty)
                return false
            }
            
            return true
        }
        
        guard let from = Conn.received?.params?["from"] as? String else {
            Conn.sendError(error: .notFound(.from))
            return false
        }
        guard WManager.loadWalletBy(address: from, type: .icx) != nil else {
            Conn.sendError(error: .notFound(.address))
            return false
        }
        
        guard let info = WManager.walletInfoList.filter({ $0.address == from }).first else { return false }
        guard let value = Conn.received?.params?["value"] as? String else {
            Conn.sendError(error: ConnectError.notFound(.value))
            return false
        }
        guard let converted = BigUInt(value.prefix0xRemoved(), radix: 16) else {
            Conn.sendError(error: ConnectError.invalidParameter(.value))
            return false
        }
        
        
        
        if Conn.action == "sendICX" {
            if let balance = WManager.walletBalanceList[info.address] {
                if balance == 0 || balance < converted {
                    Conn.sendError(error: ConnectError.insufficient(.balance))
                    return false
                }
            } else if !WManager.isBalanceLoadCompleted {
                return false
            } else {
                Conn.sendError(error: ConnectError.network("Could not fetch balance."))
                return false
            }
        } else if Conn.action == "sendToken" {
            guard let contract = Conn.received?.params?["contract"] as? String else {
                Conn.sendError(error: ConnectError.notFound(.contractAddress))
                return false
            }
            
            let balanceResult = WManager.getIRCTokenBalance(dependedAddress: from, contractAddress: contract)
            
            switch balanceResult {
            case .failure(let error):
                Log.Debug("Error - \(error)")
                Conn.sendError(error: ConnectError.network(error))
                
            case .success(let result):
                guard let valueString = result.result, let tokenBalance = BigUInt(valueString.prefix0xRemoved(), radix: 16) else {
                    Conn.sendError(error: ConnectError.network("Could not fetch balance."))
                    return false
                }
                
                if tokenBalance < converted {
                    Conn.sendError(error: ConnectError.insufficient(.balance))
                    return false
                }
            }
        }
        didProceed = true
        return true
    }
    
    func action() {
        
            let storyboard = UIStoryboard(name: "Connect", bundle: nil)
            
            if Conn.action == "bind" {
                let bind = storyboard.instantiateViewController(withIdentifier: "BindView")
                self.present(bind, animated: true, completion: nil)
            } else {
                guard let from = Conn.received?.params?["from"] as? String else { return }
                
                guard let info = WManager.walletInfoList.filter({ $0.address == from }).first else {
                    Conn.sendError(error: ConnectError.notFound(.wallet(from)))
                    return
                }
                
                switch Conn.action {
                case "sign", "sendICX":
                    let sign = storyboard.instantiateViewController(withIdentifier: "BindPasswordView") as! BindPasswordViewController
                    sign.selectedWallet = info
                    self.present(sign, animated: true, completion: nil)
                    
                case "sendToken":
                    break
                    
                default:
                    Conn.sendError(error: ConnectError.notFound(.method))
                    return
                }
            }
        
    }
}