//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  PurchasesOrchestratorTests.swift
//
//  Created by Andrés Boedo on 1/9/21.

import Foundation
import Nimble
@testable import RevenueCat
import StoreKit
import XCTest

class PurchasesOrchestratorTests: StoreKitConfigTestCase {

    private var productsManager: MockProductsManager!
    private var storeKitWrapper: MockStoreKitWrapper!
    private var systemInfo: MockSystemInfo!
    private var subscriberAttributesManager: MockSubscriberAttributesManager!
    private var operationDispatcher: MockOperationDispatcher!
    private var receiptFetcher: MockReceiptFetcher!
    private var customerInfoManager: MockCustomerInfoManager!
    private var backend: MockBackend!
    private var currentUserProvider: MockCurrentUserProvider!
    private var transactionsManager: MockTransactionsManager!
    private var deviceCache: MockDeviceCache!
    private var mockManageSubsHelper: MockManageSubscriptionsHelper!
    private var mockBeginRefundRequestHelper: MockBeginRefundRequestHelper!

    private var orchestrator: PurchasesOrchestrator!

    override func setUpWithError() throws {
        try super.setUpWithError()
        try setUpSystemInfo()
        productsManager = MockProductsManager(systemInfo: systemInfo,
                                              requestTimeout: Configuration.storeKitRequestTimeoutDefault)
        operationDispatcher = MockOperationDispatcher()
        receiptFetcher = MockReceiptFetcher(requestFetcher: MockRequestFetcher(), systemInfo: systemInfo)
        deviceCache = MockDeviceCache(systemInfo: systemInfo)
        backend = MockBackend()
        customerInfoManager = MockCustomerInfoManager(operationDispatcher: OperationDispatcher(),
                                                      deviceCache: deviceCache,
                                                      backend: backend,
                                                      systemInfo: systemInfo)
        currentUserProvider = MockCurrentUserProvider(mockAppUserID: "appUserID")
        transactionsManager = MockTransactionsManager(storeKit2Setting: systemInfo.storeKit2Setting,
                                                      receiptParser: MockReceiptParser())
        let attributionFetcher = MockAttributionFetcher(attributionFactory: MockAttributionTypeFactory(),
                                                        systemInfo: systemInfo)
        subscriberAttributesManager = MockSubscriberAttributesManager(
            backend: backend,
            deviceCache: deviceCache,
            operationDispatcher: MockOperationDispatcher(),
            attributionFetcher: attributionFetcher,
            attributionDataMigrator: MockAttributionDataMigrator())
        mockManageSubsHelper = MockManageSubscriptionsHelper(systemInfo: systemInfo,
                                                             customerInfoManager: customerInfoManager,
                                                             currentUserProvider: currentUserProvider)
        mockBeginRefundRequestHelper = MockBeginRefundRequestHelper(systemInfo: systemInfo,
                                                                    customerInfoManager: customerInfoManager,
                                                                    currentUserProvider: currentUserProvider)
        setupStoreKitWrapper()
        setUpOrchestrator()
        setUpStoreKit2Listener()
    }

    fileprivate func setUpStoreKit2Listener() {
        if #available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *) {
            self.orchestrator._storeKit2TransactionListener = MockStoreKit2TransactionListener()
        }
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    var mockStoreKit2TransactionListener: MockStoreKit2TransactionListener? {
        return self.orchestrator.storeKit2TransactionListener as? MockStoreKit2TransactionListener
    }

    fileprivate func setUpSystemInfo(
        finishTransactions: Bool = true,
        storeKit2Setting: StoreKit2Setting = .default
    ) throws {
        let platformInfo = Purchases.PlatformInfo(flavor: "xyz", version: "1.2.3")

        self.systemInfo = try MockSystemInfo(platformInfo: platformInfo,
                                             finishTransactions: finishTransactions,
                                             storeKit2Setting: storeKit2Setting)
    }

    fileprivate func setupStoreKitWrapper() {
        storeKitWrapper = MockStoreKitWrapper()
        storeKitWrapper.mockAddPaymentTransactionState = .purchased
        storeKitWrapper.mockCallUpdatedTransactionInstantly = true
    }

    fileprivate func setUpOrchestrator() {
        orchestrator = PurchasesOrchestrator(productsManager: productsManager,
                                             storeKitWrapper: storeKitWrapper,
                                             systemInfo: systemInfo,
                                             subscriberAttributesManager: subscriberAttributesManager,
                                             operationDispatcher: operationDispatcher,
                                             receiptFetcher: receiptFetcher,
                                             customerInfoManager: customerInfoManager,
                                             backend: backend,
                                             currentUserProvider: currentUserProvider,
                                             transactionsManager: transactionsManager,
                                             deviceCache: deviceCache,
                                             manageSubscriptionsHelper: mockManageSubsHelper,
                                             beginRefundRequestHelper: mockBeginRefundRequestHelper)
        storeKitWrapper.delegate = orchestrator
    }

    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    fileprivate func setUpOrchestrator(
        storeKit2TransactionListener: StoreKit2TransactionListener,
        storeKit2StorefrontListener: StoreKit2StorefrontListener
    ) {
        self.orchestrator = PurchasesOrchestrator(productsManager: self.productsManager,
                                                  storeKitWrapper: self.storeKitWrapper,
                                                  systemInfo: self.systemInfo,
                                                  subscriberAttributesManager: self.subscriberAttributesManager,
                                                  operationDispatcher: self.operationDispatcher,
                                                  receiptFetcher: self.receiptFetcher,
                                                  customerInfoManager: self.customerInfoManager,
                                                  backend: self.backend,
                                                  currentUserProvider: self.currentUserProvider,
                                                  transactionsManager: self.transactionsManager,
                                                  deviceCache: self.deviceCache,
                                                  manageSubscriptionsHelper: self.mockManageSubsHelper,
                                                  beginRefundRequestHelper: self.mockBeginRefundRequestHelper,
                                                  storeKit2TransactionListener: storeKit2TransactionListener,
                                                  storeKit2StorefrontListener: storeKit2StorefrontListener)
        self.storeKitWrapper.delegate = self.orchestrator
    }

    func testPurchaseSK1PackageSendsReceiptToBackendIfSuccessful() async throws {
        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo
        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)

        let product = try await fetchSk1Product()
        let storeProduct = try await fetchSk1StoreProduct()
        let package = Package(identifier: "package",
                              packageType: .monthly,
                              storeProduct: storeProduct,
                              offeringIdentifier: "offering")

        let payment = storeKitWrapper.payment(withProduct: product)

        _ = await withCheckedContinuation { continuation in
            orchestrator.purchase(sk1Product: product,
                                  payment: payment,
                                  package: package) { transaction, customerInfo, error, userCancelled in
                continuation.resume(returning: (transaction, customerInfo, error, userCancelled))
            }
        }

        expect(self.backend.invokedPostReceiptDataCount) == 1
    }

    func testPurchaseSK1PromotionalOffer() async throws {
        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo
        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)
        backend.stubbedPostOfferCompletionResult = .success(("signature", "identifier", UUID(), 12345))

        let product = try await fetchSk1Product()

        let storeProductDiscount = MockStoreProductDiscount(offerIdentifier: "offerid1",
                                                            currencyCode: product.priceLocale.currencyCode,
                                                            price: 11.1,
                                                            localizedPriceString: "$11.10",
                                                            paymentMode: .payAsYouGo,
                                                            subscriptionPeriod: .init(value: 1, unit: .month),
                                                            numberOfPeriods: 2,
                                                            type: .promotional)

        _ = try await withCheckedThrowingContinuation { continuation in
            orchestrator.promotionalOffer(forProductDiscount: storeProductDiscount,
                                          product: StoreProduct(sk1Product: product)) { result in
                continuation.resume(with: result)
            }
        }

        expect(self.backend.invokedPostOfferCount) == 1
        expect(self.backend.invokedPostOfferParameters?.offerIdentifier) == storeProductDiscount.offerIdentifier
    }

    func testPurchaseSK1PackageWithDiscountSendsReceiptToBackendIfSuccessful() async throws {
        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo
        backend.stubbedPostOfferCompletionResult = .success(("signature", "identifier", UUID(), 12345))
        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)

        let product = try await fetchSk1Product()
        let storeProduct = StoreProduct(sk1Product: product)
        let package = Package(identifier: "package",
                              packageType: .monthly,
                              storeProduct: storeProduct,
                              offeringIdentifier: "offering")

        let discount = MockStoreProductDiscount(offerIdentifier: "offerid1",
                                                currencyCode: storeProduct.currencyCode,
                                                price: 11.1,
                                                localizedPriceString: "$11.10",
                                                paymentMode: .payAsYouGo,
                                                subscriptionPeriod: .init(value: 1, unit: .month),
                                                numberOfPeriods: 2,
                                                type: .promotional)
        let offer = PromotionalOffer(discount: discount,
                                     signedData: .init(identifier: "",
                                                       keyIdentifier: "",
                                                       nonce: UUID(),
                                                       signature: "",
                                                       timestamp: 0))

        _ = await withCheckedContinuation { continuation in
            orchestrator.purchase(sk1Product: product,
                                  promotionalOffer: offer,
                                  package: package) { transaction, customerInfo, error, userCancelled in
                continuation.resume(returning: (transaction, customerInfo, error, userCancelled))
            }
        }

        expect(self.backend.invokedPostReceiptDataCount) == 1
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testPurchaseSK2PackageReturnsCorrectValues() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let mockTransaction = try await createTransactionWithPurchase()

        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo
        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)
        mockStoreKit2TransactionListener?.mockTransaction = .init(mockTransaction)

        let product = try await self.fetchSk2Product()

        let (transaction, customerInfo, userCancelled) = try await orchestrator.purchase(sk2Product: product,
                                                                                         promotionalOffer: nil)

        expect(transaction?.sk2Transaction) == mockTransaction
        expect(userCancelled) == false

        let expectedCustomerInfo = try CustomerInfo(data: [
            "request_date": "2019-08-16T10:30:42Z",
            "subscriber": [
                "first_seen": "2019-07-17T00:05:54Z",
                "original_app_user_id": "",
                "subscriptions": [:],
                "other_purchases": [:]
            ]])
        expect(customerInfo) == expectedCustomerInfo
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testPurchaseSK2PackageHandlesPurchaseResult() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo
        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)

        let storeProduct = StoreProduct.from(product: try await fetchSk2StoreProduct())
        let package = Package(identifier: "package",
                              packageType: .monthly,
                              storeProduct: storeProduct,
                              offeringIdentifier: "offering")

        _ = await withCheckedContinuation { continuation in
            orchestrator.purchase(product: storeProduct,
                                  package: package) { transaction, customerInfo, error, userCancelled in
                continuation.resume(returning: (transaction, customerInfo, error, userCancelled))
            }
        }

        let mockListener = try XCTUnwrap(orchestrator.storeKit2TransactionListener as? MockStoreKit2TransactionListener)
        expect(mockListener.invokedHandle) == true
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testPurchaseSK2PackageSendsReceiptToBackendIfSuccessful() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo
        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)

        let product = try await fetchSk2Product()

        _ = try await orchestrator.purchase(sk2Product: product, promotionalOffer: nil)

        expect(self.backend.invokedPostReceiptDataCount) == 1
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testPurchaseSK2PackageSkipsIfPurchaseFailed() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        testSession.failTransactionsEnabled = true
        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo
        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)

        let product = try await fetchSk2Product()
        let storeProduct = StoreProduct(sk2Product: product)
        let discount = MockStoreProductDiscount(offerIdentifier: "offerid1",
                                                currencyCode: storeProduct.currencyCode,
                                                price: 11.1,
                                                localizedPriceString: "$11.10",
                                                paymentMode: .payAsYouGo,
                                                subscriptionPeriod: .init(value: 1, unit: .month),
                                                numberOfPeriods: 4,
                                                type: .promotional)
        let offer = PromotionalOffer(discount: discount,
                                     signedData: .init(identifier: "",
                                                       keyIdentifier: "",
                                                       nonce: UUID(),
                                                       signature: "",
                                                       timestamp: 0))

        do {
            _ = try await orchestrator.purchase(sk2Product: product, promotionalOffer: offer)
            XCTFail("Expected error")
        } catch {
            expect(self.backend.invokedPostReceiptData) == false
            let mockListener = try XCTUnwrap(
                orchestrator.storeKit2TransactionListener as? MockStoreKit2TransactionListener
            )
            expect(mockListener.invokedHandle) == false
        }
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testPurchaseSK2PackageReturnsMissingReceiptErrorIfSendReceiptFailed() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        receiptFetcher.shouldReturnReceipt = false
        let expectedError = ErrorUtils.missingReceiptFileError()

        let product = try await fetchSk2Product()

        do {
            _ = try await orchestrator.purchase(sk2Product: product, promotionalOffer: nil)

            XCTFail("Expected error")
        } catch {
            expect(error).to(matchError(expectedError))

            let mockListener = try XCTUnwrap(
                orchestrator.storeKit2TransactionListener as? MockStoreKit2TransactionListener
            )
            expect(mockListener.invokedHandle) == true
        }
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testStoreKit2TransactionListenerDelegate() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo
        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)

        let customerInfo = try await orchestrator.transactionsUpdated()

        expect(self.backend.invokedPostReceiptData).to(beTrue())
        expect(self.backend.invokedPostReceiptDataParameters?.isRestore).to(beFalse())
        expect(customerInfo) == mockCustomerInfo
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testStoreKit2TransactionListenerDelegateWithObserverMode() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        try setUpSystemInfo(finishTransactions: false)
        setUpOrchestrator()

        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)
        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo

        let customerInfo = try await orchestrator.transactionsUpdated()

        expect(self.backend.invokedPostReceiptData).to(beTrue())
        expect(self.backend.invokedPostReceiptDataParameters?.isRestore).to(beTrue())
        expect(customerInfo) == mockCustomerInfo
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testPurchaseSK2PromotionalOffer() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        customerInfoManager.stubbedCachedCustomerInfoResult = mockCustomerInfo
        backend.stubbedPostReceiptResult = .success(mockCustomerInfo)
        backend.stubbedPostOfferCompletionResult = .success(("signature", "identifier", UUID(), 12345))

        let storeProduct = try await self.fetchSk2StoreProduct()

        let storeProductDiscount = MockStoreProductDiscount(offerIdentifier: "offerid1",
                                                            currencyCode: storeProduct.currencyCode,
                                                            price: 11.1,
                                                            localizedPriceString: "$11.10",
                                                            paymentMode: .payAsYouGo,
                                                            subscriptionPeriod: .init(value: 1, unit: .month),
                                                            numberOfPeriods: 3,
                                                            type: .promotional)

        _ = try await orchestrator.promotionalOffer(forProductDiscount: storeProductDiscount,
                                                    product: storeProduct)

        expect(self.backend.invokedPostOfferCount) == 1
        expect(self.backend.invokedPostOfferParameters?.offerIdentifier) == storeProductDiscount.offerIdentifier
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testDoesNotListenForSK2TransactionsWithSK2Disabled() throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let transactionListener = MockStoreKit2TransactionListener()

        try self.setUpSystemInfo(storeKit2Setting: .disabled)

        self.setUpOrchestrator(storeKit2TransactionListener: transactionListener,
                               storeKit2StorefrontListener: StoreKit2StorefrontListener(delegate: nil))

        expect(transactionListener.invokedListenForTransactions) == false
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testDoesNotListenForSK2TransactionsWithSK2EnabledOnlyForOptimizations() throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let transactionListener = MockStoreKit2TransactionListener()

        try self.setUpSystemInfo(storeKit2Setting: .enabledOnlyForOptimizations)

        self.setUpOrchestrator(storeKit2TransactionListener: transactionListener,
                               storeKit2StorefrontListener: StoreKit2StorefrontListener(delegate: nil))

        expect(transactionListener.invokedListenForTransactions) == false
    }

    @available(iOS 15.0, tvOS 15.0, watchOS 8.0, macOS 12.0, *)
    func testListensForSK2TransactionsWithSK2Enabled() throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let transactionListener = MockStoreKit2TransactionListener()

        try self.setUpSystemInfo(storeKit2Setting: .enabledForCompatibleDevices)

        self.setUpOrchestrator(storeKit2TransactionListener: transactionListener,
                               storeKit2StorefrontListener: StoreKit2StorefrontListener(delegate: nil))

        expect(transactionListener.invokedListenForTransactions) == true
        expect(transactionListener.invokedListenForTransactionsCount) == 1
    }

    func testShowManageSubscriptionsCallsCompletionWithErrorIfThereIsAFailure() {
        let message = "Failed to get managementURL from CustomerInfo. Details: customerInfo is nil."
        mockManageSubsHelper.mockError = ErrorUtils.customerInfoError(withMessage: message)
        var receivedError: Error?
        var completionCalled = false
        orchestrator.showManageSubscription { error in
            completionCalled = true
            receivedError = error
        }

        expect(completionCalled).toEventually(beTrue())
        expect(receivedError).toNot(beNil())
        expect(receivedError).to(matchError(ErrorCode.customerInfoError))
    }

    @available(iOS 15.0, macCatalyst 15.0, *)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    @available(macOS, unavailable)
    func testBeginRefundForProductCompletesWithoutErrorAndPassesThroughStatusIfSuccessful() async throws {
        let expectedStatus = RefundRequestStatus.userCancelled
        mockBeginRefundRequestHelper.mockRefundRequestStatus = expectedStatus

        let refundStatus = try await orchestrator.beginRefundRequest(forProduct: "1234")
        expect(refundStatus) == expectedStatus
    }

    @available(iOS 15.0, macCatalyst 15.0, *)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    @available(macOS, unavailable)
    func testBeginRefundForProductCompletesWithErrorIfThereIsAFailure() async {
        let expectedError = ErrorUtils.beginRefundRequestError(withMessage: "test")
        mockBeginRefundRequestHelper.mockError = expectedError

        do {
            _ = try await orchestrator.beginRefundRequest(forProduct: "1235")
            XCTFail("beginRefundRequestForProduct should have thrown an error")
        } catch {
            expect(error).to(matchError(expectedError))
        }
    }

    @available(iOS 15.0, macCatalyst 15.0, *)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    @available(macOS, unavailable)
    func testBeginRefundForEntitlementCompletesWithoutErrorAndPassesThroughStatusIfSuccessful() async throws {
        let expectedStatus = RefundRequestStatus.userCancelled
        mockBeginRefundRequestHelper.mockRefundRequestStatus = expectedStatus

        let receivedStatus = try await orchestrator.beginRefundRequest(forEntitlement: "1234")
        expect(receivedStatus) == expectedStatus
    }

    @available(iOS 15.0, macCatalyst 15.0, *)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    @available(macOS, unavailable)
    func testBeginRefundForEntitlementCompletesWithErrorIfThereIsAFailure() async {
        let expectedError = ErrorUtils.beginRefundRequestError(withMessage: "test")
        mockBeginRefundRequestHelper.mockError = expectedError

        do {
            _ = try await orchestrator.beginRefundRequest(forEntitlement: "1234")
            XCTFail("beginRefundRequestForEntitlement should have thrown error")
        } catch {
            expect(error).toNot(beNil())
            expect(error).to(matchError(expectedError))
        }

    }

    @available(iOS 15.0, macCatalyst 15.0, *)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    @available(macOS, unavailable)
    func testBeginRefundForActiveEntitlementCompletesWithoutErrorAndPassesThroughStatusIfSuccessful() async throws {
        let expectedStatus = RefundRequestStatus.userCancelled
        mockBeginRefundRequestHelper.mockRefundRequestStatus = expectedStatus

        let receivedStatus = try await orchestrator.beginRefundRequestForActiveEntitlement()
        expect(receivedStatus) == expectedStatus
    }

    @available(iOS 15.0, macCatalyst 15.0, *)
    @available(watchOS, unavailable)
    @available(tvOS, unavailable)
    @available(macOS, unavailable)
    func testBeginRefundForActiveEntitlementCompletesWithErrorIfThereIsAFailure() async {
        let expectedError = ErrorUtils.beginRefundRequestError(withMessage: "test")
        mockBeginRefundRequestHelper.mockError = expectedError

        do {
            _ = try await orchestrator.beginRefundRequestForActiveEntitlement()
            XCTFail("beginRefundRequestForActiveEntitlement should have thrown error")
        } catch {
            expect(error).toNot(beNil())
            expect(error).to(matchError(expectedError))
            expect(error.localizedDescription).to(equal(expectedError.localizedDescription))
        }
    }

}

private extension PurchasesOrchestratorTests {

    @MainActor
    func fetchSk1Product() async throws -> SK1Product {
        return MockSK1Product(
            mockProductIdentifier: Self.productID,
            mockSubscriptionGroupIdentifier: "group1"
        )
    }

    @MainActor
    func fetchSk1StoreProduct() async throws -> SK1StoreProduct {
        return try await SK1StoreProduct(sk1Product: fetchSk1Product())
    }

    var mockCustomerInfo: CustomerInfo {
        // swiftlint:disable:next force_try
        try! CustomerInfo(data: [
            "request_date": "2019-08-16T10:30:42Z",
            "subscriber": [
                "first_seen": "2019-07-17T00:05:54Z",
                "original_app_user_id": "",
                "subscriptions": [:],
                "other_purchases": [:]
            ]])
    }

}
