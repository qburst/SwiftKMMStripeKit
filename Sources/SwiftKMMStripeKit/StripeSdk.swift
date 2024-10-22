// The Swift Programming Language
// https://docs.swift.org/swift-book
//  Stripesdk.swift
//  iosApp
//
//  Created by abdul basith on 05/08/24.
//  Copyright © 2024 orgName. All rights reserved.
//


import Foundation
import Stripe
import StripePaymentSheet
import UIKit
import ComposeApp


public class StripeSdk : NSObject, SharedStripeRepository, STPBankSelectionViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
   
    var cardFieldView: CardFieldView? = nil
    var cardFormView: CardFormView? = nil
    private var paymentSheet: PaymentSheet?
    private var paymentSheetClientSecret: String?
    var confirmPaymentClientSecret: String? = nil
    
    var confirmPaymentResolver: Any? = nil
    
    var urlScheme: String? = nil
    var merchantIdentifier: String? = nil
    
    
    public override init() {}
    
    
    public func initialise(params: [String : Any]) throws {
        
        let publishableKey = params["publishableKey"] as! String
        let appInfo = params["appInfo"] as! NSDictionary
        let stripeAccountId = params["stripeAccountId"] as? String
        let params3ds = params["threeDSecureParams"] as? NSDictionary
        let urlScheme = params["urlScheme"] as? String
        let merchantIdentifier = params["merchantIdentifier"] as? String
        
        if let params3ds = params3ds {
            configure3dSecure(params3ds)
        }
        
        self.urlScheme = urlScheme
        
        STPAPIClient.shared.publishableKey = publishableKey
        StripeAPI.defaultPublishableKey = publishableKey
        STPAPIClient.shared.stripeAccount = stripeAccountId
        
        
        let name = appInfo["name"] as? String ?? ""
        let partnerId = appInfo["partnerId"] as? String ?? ""
        let version = appInfo["version"] as? String ?? ""
        let url = appInfo["url"] as? String ?? ""
        
        STPAPIClient.shared.appInfo = STPAppInfo(name: name, partnerId: partnerId, version: version, url: url)
        self.merchantIdentifier = merchantIdentifier
        
        
    }
    
    func configure3dSecure(_ params: NSDictionary) {
        let threeDSCustomizationSettings = STPPaymentHandler.shared().threeDSCustomizationSettings
        let uiCustomization = Mappers.mapUICustomization(params)
        threeDSCustomizationSettings.uiCustomization = uiCustomization
    }
    
    
    public func createPaymentMethod(params: [String : Any], options: [String : Any], onSuccess: @escaping ([String : Any]) -> Void, onError: @escaping (KotlinThrowable) -> Void) throws {
        
        let type = Mappers.mapToPaymentMethodType(type: params["paymentMethodType"] as? String)
        guard let paymentMethodType = type else {
            onError(KotlinThrowable(message:  Errors.createError(ErrorType.Failed, "You must provide paymentMethodType").description))
            return
        }
        
        var paymentMethodParams: STPPaymentMethodParams?
        let factory = PaymentMethodFactory.init(
            paymentMethodData: params["paymentMethodData"] as? NSDictionary,
            options: options as NSDictionary,
            cardFieldView: cardFieldView,
            cardFormView: cardFormView
        )
        
        do {
            paymentMethodParams = try factory.createParams(paymentMethodType: paymentMethodType)
        } catch  {
            onError(KotlinThrowable(message: Errors.createError(ErrorType.Failed, error.localizedDescription).description))
            return
        }
        
        if let paymentMethodParams = paymentMethodParams {
            STPAPIClient.shared.createPaymentMethod(with: paymentMethodParams) { paymentMethod, error in
                if let createError = error {
                    onError(KotlinThrowable(message:  Errors.createError(ErrorType.Failed, createError.localizedDescription).description))
                    
                } else {
                    onSuccess(Mappers.mapFromPaymentMethod(paymentMethod) as! [String : Any])
                }
            }
        } else {
            onError(KotlinThrowable(message:  Errors.createError(ErrorType.Unknown, "Unhandled error occured").description))
        }
    }
    
    
    public func handleNextAction(
        paymentIntentClientSecret: String,
        returnURL: String?,
        onSuccess: @escaping ([String : Any]) -> Void, onError: @escaping (KotlinThrowable) -> Void) throws {
        let paymentHandler = STPPaymentHandler.shared()
            paymentHandler.handleNextAction(forPayment: paymentIntentClientSecret, with: self, returnURL: returnURL) { status, paymentIntent, handleActionError in
            switch status {
            case .failed:
                if let error = handleActionError {
                    onError(KotlinThrowable(message:  Errors.createError(ErrorType.Failed, "Failed").description))
                 
                } else {
                    onError(KotlinThrowable(message:  Errors.createError(ErrorType.Failed, "Failed: Unknown failure").description))
                  
                }
            case .canceled:
                if let lastError = paymentIntent?.lastPaymentError {
                    
                    onError(KotlinThrowable(message:  Errors.createError(ErrorType.Failed, "Canceled").description))
                } else {
                    onError(KotlinThrowable(message:  Errors.createError(ErrorType.Failed, "Cancled: The payment has been canceled").description))
                
                }
            case .succeeded:
                if let paymentIntent = paymentIntent {
                    let result = Mappers.createResult("paymentIntent", Mappers.mapFromPaymentIntent(paymentIntent: paymentIntent) as NSDictionary)
                    onSuccess(result as! [String : Any])
                } else {
                    onError(KotlinThrowable(message:  Errors.createError(ErrorType.Failed, "Success: Unknown success").description))
                
                }
            @unknown default:
                onError(KotlinThrowable(message:  Errors.createError(ErrorType.Failed, "Unknown: Cannot complete payment").description))
            }
        }
    }
    
    public func handleNextActionForSetup(
        setupIntentClientSecret: String,
        returnURL: String?,
        onSuccess: @escaping ([String: Any]) -> Void,
        onError: @escaping (KotlinThrowable) -> Void
    ) throws {
        let paymentHandler = STPPaymentHandler.shared()
        
        paymentHandler.handleNextAction(forSetupIntent: setupIntentClientSecret, with: self, returnURL: returnURL) { status, setupIntent, handleActionError in
            switch status {
            case .failed:
                if let error = handleActionError {
                    onError(KotlinThrowable(message: Errors.createError(ErrorType.Failed, "Failed: \(error.localizedDescription)").description))
                } else {
                    onError(KotlinThrowable(message: Errors.createError(ErrorType.Failed, "Failed: Unknown failure").description))
                }
                
            case .canceled:
                if let lastError = setupIntent?.lastSetupError {
                    onError(KotlinThrowable(message: Errors.createError(ErrorType.Canceled, "Canceled: \(lastError.description)").description))
                } else {
                    onError(KotlinThrowable(message: Errors.createError(ErrorType.Canceled, "Canceled: The setup has been canceled").description))
                }
                
            case .succeeded:
                if let setupIntent = setupIntent {
                    let result = Mappers.createResult("setupIntent", Mappers.mapFromSetupIntent(setupIntent: setupIntent) as NSDictionary)
                    onSuccess(result as! [String: Any])
                } else {
                    onError(KotlinThrowable(message: Errors.createError(ErrorType.Failed, "Success: Unknown success").description))
                }
                
            @unknown default:
                onError(KotlinThrowable(message: Errors.createError(ErrorType.Failed, "Unknown: Cannot complete setup").description))
            }
        }
    }

    
    
    
    func getTopMostViewController() -> UIViewController? {
        guard let keyWindow = UIApplication.shared.connectedScenes
            .filter({ $0.activationState == .foregroundActive })
            .map({ $0 as? UIWindowScene })
            .compactMap({ $0 })
            .first?.windows
            .filter({ $0.isKeyWindow }).first else {
                return nil
        }
        var topController = keyWindow.rootViewController
        while let presentedController = topController?.presentedViewController {
            topController = presentedController
        }
        return topController
    }

    
    
    
    func confirmPayment(
        paymentIntentClientSecret: String,
        params: [String: Any]?,
        options: [String: Any],
        onSuccess: @escaping ([String: Any]) -> Void,
        onError: @escaping (KotlinThrowable) -> Void) throws {
            
            
            self.confirmPaymentClientSecret = paymentIntentClientSecret

               // Extract the payment method data from params
               let paymentMethodData = params?["paymentMethodData"] as? [String: Any]

               // Check if payment method type is missing or invalid
               let (missingPaymentMethodError, paymentMethodType) = getPaymentMethodType(params: params)
               if let error = missingPaymentMethodError {
                   onError(KotlinThrowable(message: Errors.createError(ErrorType.Failed, "Missing paymentMethodData").description))
                   return
               }

               // Handle FPX payment method type specifically
               if paymentMethodType == .FPX {
                   let testOfflineBank = paymentMethodData?["testOfflineBank"] as? Bool
                   if testOfflineBank == false || testOfflineBank == nil {
                       payWithFPX(paymentIntentClientSecret: paymentIntentClientSecret)
                       return
                   }
               }

               // Create payment intent parameters
               let (error, paymentIntentParams) = createPaymentIntentParams(
                   paymentIntentClientSecret: paymentIntentClientSecret,
                   paymentMethodType: paymentMethodType,
                   paymentMethodData: paymentMethodData,
                   options: options
               )

               // Handle errors during payment intent creation
               if let error = error {
                   onError(KotlinThrowable(message: Errors.createError(ErrorType.Failed, error.description).description))
               } else {
                   // Use the STPPaymentHandler to confirm the payment
                   STPPaymentHandler.shared().confirmPayment(paymentIntentParams, with: self) { status, paymentIntent, error in
                       self.onCompleteConfirmPayment(status: status, paymentIntent: paymentIntent, error: error)
                       if let error = error {
                           onError(KotlinThrowable(message: Errors.createError(ErrorType.Failed, error.localizedDescription).description))
                       } else {
                           onSuccess([:])
                       }
                   }
               }

    }
    
    func createPaymentIntentParams(
        paymentIntentClientSecret: String,
        paymentMethodType: STPPaymentMethodType?,
        paymentMethodData: [String: Any]?,
        options: [String: Any]
    ) -> ([String: Any]?, STPPaymentIntentParams) {
        var err: [String: Any]? = nil

        let paymentIntentParams: STPPaymentIntentParams = {
            // If payment method data is not supplied, assume payment method was attached via collectBankAccount
            if paymentMethodType == .USBankAccount && paymentMethodData == nil {
                return STPPaymentIntentParams(clientSecret: paymentIntentClientSecret, paymentMethodType: .USBankAccount)
            } else {
                guard let paymentMethodType = paymentMethodType else {
                    return STPPaymentIntentParams(clientSecret: paymentIntentClientSecret)
                }

                // Create a factory to handle payment method creation
                let factory = PaymentMethodFactory(paymentMethodData: paymentMethodData as NSDictionary?, options: options as NSDictionary, cardFieldView: cardFieldView, cardFormView: cardFormView)
                
                let paymentMethodId = paymentMethodData?["paymentMethodId"] as? String
                let parameters = STPPaymentIntentParams(clientSecret: paymentIntentClientSecret)

                // If paymentMethodId exists, use it, otherwise create paymentMethodParams
                if let paymentMethodId = paymentMethodId {
                    parameters.paymentMethodId = paymentMethodId
                } else {
                    do {
                        parameters.paymentMethodParams = try factory.createParams(paymentMethodType: paymentMethodType)
                    } catch {
                        err = Errors.createError(ErrorType.Failed, error) as! [String : Any]
                    }
                }

                // Attempt to create paymentMethodOptions and mandateData
                do {
                    parameters.paymentMethodOptions = try factory.createOptions(paymentMethodType: paymentMethodType)
                    parameters.mandateData = factory.createMandateData()
                } catch {
                    err = Errors.createError(ErrorType.Failed, error) as! [String : Any]
                }

                return parameters
            }
        }()

        // Set up future usage and return URL if applicable
        if let setupFutureUsage = options["setupFutureUsage"] as? String {
            paymentIntentParams.setupFutureUsage = Mappers.mapToPaymentIntentFutureUsage(usage: setupFutureUsage)
        }

        if let urlScheme = urlScheme {
            paymentIntentParams.returnURL = Mappers.mapToReturnURL(urlScheme: urlScheme)
        }

        // Map shipping details from paymentMethodData
        if let shippingDetails = paymentMethodData?["shippingDetails"] as? [String: Any] {
            paymentIntentParams.shipping = Mappers.mapToShippingDetails(shippingDetails: shippingDetails as NSDictionary)
        }

        return (err, paymentIntentParams)
    }


    
    
    
    public func confirmSetupIntent(setupIntentClientSecret: String,
                                   params: [String: Any],
                                   options: [String: Any],
                                   onSuccess: @escaping ([String: Any]) -> Void,
                                   onError: @escaping (Error) -> Void) {
        
        // Map the payment method type
        guard let paymentMethodType = Mappers.mapToPaymentMethodType(type: params["paymentMethodType"] as? String) else {
            onError(Errors.createError(ErrorType.Failed, "You must provide paymentMethodType") as! any Error)
            return
        }
        
        let paymentMethodData = params["paymentMethodData"] as? [String: Any]
        var err: Error?
        
        // Create setup intent confirm parameters
        let setupIntentParams: STPSetupIntentConfirmParams = {
            if paymentMethodType == .USBankAccount && paymentMethodData == nil {
                // Case for USBankAccount without payment method data
                return STPSetupIntentConfirmParams(clientSecret: setupIntentClientSecret, paymentMethodType: .USBankAccount)
            } else {
                // Otherwise create params using PaymentMethodFactory
                let factory = PaymentMethodFactory(
                    paymentMethodData: paymentMethodData as NSDictionary?,
                    options: options as NSDictionary,
                    cardFieldView: cardFieldView,
                    cardFormView: cardFormView
                )
                let parameters = STPSetupIntentConfirmParams(clientSecret: setupIntentClientSecret)
                
                if let paymentMethodId = paymentMethodData?["paymentMethodId"] as? String {
                    parameters.paymentMethodID = paymentMethodId
                } else {
                    do {
                        parameters.paymentMethodParams = try factory.createParams(paymentMethodType: paymentMethodType)
                    } catch let error {
                        err = Errors.createError(ErrorType.Failed, error.localizedDescription) as! any Error
                    }
                }
                
                parameters.mandateData = factory.createMandateData()
                return parameters
            }
        }()
        
        // Handle any errors that occurred during param creation
        if let creationError = err {
            onError(creationError)
            return
        }
        
        // Optionally set the return URL scheme
        if let urlScheme = urlScheme {
            setupIntentParams.returnURL = Mappers.mapToReturnURL(urlScheme: urlScheme)
        }
        
        // Confirm the setup intent using Stripe's payment handler
        let paymentHandler = STPPaymentHandler.shared()
        paymentHandler.confirmSetupIntent(setupIntentParams, with: self) { status, setupIntent, error in
            switch status {
            case .failed:
                onError(Errors.createError(ErrorType.Failed, error?.localizedDescription ?? "Unknown error") as! any Error)
                
            case .canceled:
                if let lastError = setupIntent?.lastSetupError {
                    onError(Errors.createError(ErrorType.Canceled, lastError.message) as! any Error)
                } else {
                    onError(Errors.createError(ErrorType.Canceled, "The setup intent has been canceled") as! any Error)
                }
                
            case .succeeded:
                if let intent = setupIntent {
                    let mappedIntent = Mappers.mapFromSetupIntent(setupIntent: intent)
                    onSuccess(Mappers.createResult("setupIntent", mappedIntent) as! [String: Any])
                } else {
                    onError(Errors.createError(ErrorType.Unknown, "Setup intent succeeded but returned nil") as! any Error)
                }
                
            @unknown default:
                onError(Errors.createError(ErrorType.Unknown, "Unknown status received") as! any Error)
            }
        }
    }
    
    func getPaymentMethodType(params: [String: Any]?) -> ([String: Any]?, STPPaymentMethodType?) {
        if let params = params {
            guard let paymentMethodType = Mappers.mapToPaymentMethodType(type: params["paymentMethodType"] as? String) else {
                let error = Errors.createCustomError(code: ErrorType.Failed, message: "You must provide paymentMethodType")
                return (error, nil)
            }
            return (nil, paymentMethodType)
        } else {
            // If params aren't provided, it means we expect that the payment method was attached on the server side
            return (nil, nil)
        }
    }
    
    
    func payWithFPX(paymentIntentClientSecret: String) {
        let vc = STPBankSelectionViewController(bankMethod: .FPX)
        vc.delegate = self

        DispatchQueue.main.async {
            vc.presentationController?.delegate = self
            
            if let window = UIApplication.shared.delegate?.window {
                window?.rootViewController?.present(vc, animated: true, completion: nil)
            }
        }
    }
    
    public func bankSelectionViewController(_ bankViewController: STPBankSelectionViewController, didCreatePaymentMethodParams paymentMethodParams: STPPaymentMethodParams) {
        guard let clientSecret = confirmPaymentClientSecret else {
            Errors.createError(ErrorType.Failed, "Missing paymentIntentClientSecret")
            return
        }
        let paymentIntentParams = STPPaymentIntentParams(clientSecret: clientSecret)
        paymentIntentParams.paymentMethodParams = paymentMethodParams
        
        if let urlScheme = urlScheme {
            paymentIntentParams.returnURL = Mappers.mapToReturnURL(urlScheme: urlScheme)
        }
        let paymentHandler = STPPaymentHandler.shared()
        bankViewController.dismiss(animated: true)
        paymentHandler.confirmPayment(paymentIntentParams, with: self, completion: onCompleteConfirmPayment)
    }

    
    func onCompleteConfirmPayment(status: STPPaymentHandlerActionStatus, paymentIntent: STPPaymentIntent?, error: NSError?) {
        self.confirmPaymentClientSecret = nil
        
        switch status {
        case .failed:
            if let error = error {
                (Errors.createError(ErrorType.Failed, error.localizedDescription))
            }
            
        case .canceled:
            let statusCode: String
            if paymentIntent?.status == .requiresPaymentMethod {
                statusCode = ErrorType.Failed
            } else {
                statusCode = ErrorType.Canceled
            }
            
            if let lastPaymentError = paymentIntent?.lastPaymentError {
                (Errors.createError(statusCode, lastPaymentError.description))
            } else {
                (Errors.createError(statusCode, "The payment has been canceled"))
            }
            
        case .succeeded:
            if let paymentIntent = paymentIntent {
                let intent = Mappers.mapFromPaymentIntent(paymentIntent: paymentIntent)
                (Mappers.createResult("paymentIntent", intent as NSDictionary))
            }
            
        @unknown default:
            (Errors.createError(ErrorType.Unknown, "Cannot complete the payment"))
        }
    }

}


extension StripeSdk: STPAuthenticationContext {
    
    public func authenticationPresentingViewController() -> UIViewController {
        if Thread.isMainThread {
            return getTopMostViewControllerFromWindow()
        } else {
            var topMostViewController: UIViewController?
            DispatchQueue.main.sync {
                topMostViewController = getTopMostViewControllerFromWindow()
            }
            return topMostViewController ?? UIViewController()
        }
    }

    private func getTopMostViewControllerFromWindow() -> UIViewController {
        // Find the key window in the connected scenes
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        
        guard let rootViewController = keyWindow?.rootViewController else {
            return UIViewController() // Return a default empty controller if no root found
        }
        
        var topController: UIViewController = rootViewController
        // Traverse through presented view controllers
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }

        // Ensure the top controller's view is in a window before returning it
        guard topController.view.window != nil else {
            return UIViewController() // Not in the window hierarchy, return a default
        }

        return topController
    }
}
