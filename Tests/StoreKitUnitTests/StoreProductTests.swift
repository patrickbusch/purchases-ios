//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  StoreProductTests.swift
//
//  Created by Andrés Boedo on 1/9/21.

import Nimble
@testable import RevenueCat
import StoreKitTest
import XCTest

class StoreProductTests: StoreKitConfigTestCase {

    private var sk1Fetcher: ProductsFetcherSK1!

    override func setUp() {
        super.setUp()

        self.sk1Fetcher = ProductsFetcherSK1(productsRequestFactory: ProductsRequestFactory(),
                                             requestTimeout: Self.requestTimeout)
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
    func testSK1AndSK2DetailsAreEquivalent() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let productIdentifiers = Set([
            "com.revenuecat.monthly_4.99.1_week_intro",
            "com.revenuecat.annual_39.99.2_week_intro",
            "lifetime"
        ])
        let sk1StoreProducts = try await self.sk1Fetcher.products(withIdentifiers: productIdentifiers)
        let sk1StoreProductsByID = sk1StoreProducts.dictionaryWithKeys { $0.productIdentifier }

        let sk2StoreProducts = try await ProductsFetcherSK2().products(identifiers: productIdentifiers)
        let sk2StoreProductsByID = sk2StoreProducts.dictionaryWithKeys { $0.productIdentifier }

        expect(sk1StoreProducts.count) == productIdentifiers.count
        expect(sk1StoreProducts.count) == sk2StoreProducts.count

        for sk1ProductID in sk1StoreProductsByID.keys {
            let sk1Product = try XCTUnwrap(sk1StoreProductsByID[sk1ProductID])
            let equivalentSK2Product = try XCTUnwrap(sk2StoreProductsByID[sk1ProductID])

            expectEqualProducts(sk1Product, equivalentSK2Product)
        }
    }

    func testSK1AndStoreProductDetailsAreEquivalent() async throws {
        let product = try await self.sk1Fetcher.product(withIdentifier: Self.productID)

        expectEqualProducts(product, StoreProduct.from(product: product))
    }

    func testSK1DiscountWithNoLocale() throws {
        let discount = MockSKProductDiscountWithNoPriceLocale()
        discount.mockPrice = 2.0

        let product = MockSK1Product(mockProductIdentifier: "product")
        product.mockDiscount = discount

        let storeProduct = StoreProduct(sk1Product: product)
        expect(storeProduct.discounts).to(haveCount(1))

        let storeDiscount = try XCTUnwrap(storeProduct.discounts.first)
        expect(storeDiscount.currencyCode).to(beNil())
        expect(storeDiscount.localizedPriceString) == "$2.00"
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
    func testSK2AndStoreProductDetailsAreEquivalent() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let product = try await ProductsFetcherSK2()
            .product(withIdentifier: Self.productID)

        expectEqualProducts(product, StoreProduct.from(product: product))
    }

    func testSk1DetailsWrapsCorrectly() throws {
        var result: Result<Set<SK1StoreProduct>, Swift.Error>!

        self.sk1Fetcher.products(withIdentifiers: Set([Self.productID])) { products in
            result = products
        }

        expect(result).toEventuallyNot(beNil(), timeout: Self.requestDispatchTimeout + .seconds(5))

        let products = try result.get()
        expect(products).to(haveCount(1))

        let sk1Product = try XCTUnwrap(products.first)
        let storeProduct = StoreProduct.from(product: sk1Product)

        expect(storeProduct.sk1Product) === sk1Product.underlyingSK1Product

        expect(storeProduct.productIdentifier) == Self.productID
        expect(storeProduct.productCategory) == .subscription
        expect(storeProduct.localizedDescription) == "Monthly subscription with a 1-week free trial"
        expect(storeProduct.currencyCode) == "USD"
        expect(storeProduct.price.description) == "4.99"
        expect(storeProduct.priceDecimalNumber).to(beCloseTo(4.99))
        expect(storeProduct.localizedPriceString) == "$4.99"
        expect(storeProduct.isFamilyShareable) == true
        expect(storeProduct.localizedTitle) == "Monthly Free Trial"
        // open the StoreKit Config file as source code to see the expected value
        expect(storeProduct.subscriptionGroupIdentifier) == "7096FF06"

        expect(storeProduct.subscriptionPeriod?.unit) == .month
        expect(storeProduct.subscriptionPeriod?.value) == 1

        let intro = try XCTUnwrap(storeProduct.introductoryDiscount)

        expect(intro.price) == 0.0
        expect(intro.priceDecimalNumber) == 0.0
        expect(intro.paymentMode) == .freeTrial
        expect(intro.offerIdentifier).to(beNil())
        expect(intro.subscriptionPeriod) == SubscriptionPeriod(value: 3, unit: .month)

        let offers = try XCTUnwrap(storeProduct.discounts)
        expect(offers).to(haveCount(2))

        expect(offers[0].price) == 40.99
        expect(offers[0].priceDecimalNumber).to(beCloseTo(40.99))
        expect(offers[0].paymentMode) == .payUpFront
        expect(offers[0].offerIdentifier) == "com.revenuecat.monthly_4.99.1_week_intro.year_discount"
        expect(offers[0].subscriptionPeriod) == SubscriptionPeriod(value: 1, unit: .year)
        expect(offers[0].numberOfPeriods) == 1

        expect(offers[1].price) == 20.15
        expect(offers[1].priceDecimalNumber).to(beCloseTo(20.15))
        expect(offers[1].paymentMode) == .payAsYouGo
        expect(offers[1].offerIdentifier) == "com.revenuecat.monthly_4.99.1_week_intro.pay_as_you_go"
        expect(offers[1].subscriptionPeriod) == SubscriptionPeriod(value: 1, unit: .month)
        expect(offers[1].numberOfPeriods) == 2
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
    func testSk2DetailsWrapsCorrectly() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let sk2Fetcher = ProductsFetcherSK2()

        let storeProduct = try await sk2Fetcher.product(withIdentifier: Self.productID)

        // Can't use `===` because `SK2Product` is a `struct`
        expect(storeProduct.sk2Product) == storeProduct.sk2Product

        expect(storeProduct.productIdentifier) == Self.productID
        expect(storeProduct.productCategory) == .subscription
        expect(storeProduct.productType) == .autoRenewableSubscription
        expect(storeProduct.localizedDescription) == "Monthly subscription with a 1-week free trial"
        expect(storeProduct.currencyCode) == "USD"
        expect(storeProduct.price.description) == "4.99"
        expect(storeProduct.priceDecimalNumber).to(beCloseTo(4.99))
        expect(storeProduct.localizedPriceString) == "$4.99"
        expect(storeProduct.isFamilyShareable) == true
        expect(storeProduct.localizedTitle) == "Monthly Free Trial"
        // open the StoreKit Config file as source code to see the expected value
        expect(storeProduct.subscriptionGroupIdentifier) == "7096FF06"

        expect(storeProduct.subscriptionPeriod?.unit) == .month
        expect(storeProduct.subscriptionPeriod?.value) == 1

        let intro = try XCTUnwrap(storeProduct.introductoryDiscount)

        expect(intro.price) == 0.0
        expect(intro.priceDecimalNumber) == 0.0
        expect(intro.paymentMode) == .freeTrial
        expect(intro.type) == .introductory
        expect(intro.offerIdentifier).to(beNil())
        expect(intro.subscriptionPeriod) == SubscriptionPeriod(value: 3, unit: .month)

        let offers = try XCTUnwrap(storeProduct.discounts)
        expect(offers).to(haveCount(2))

        expect(offers[0].price) == 40.99
        expect(offers[0].priceDecimalNumber).to(beCloseTo(40.99))
        expect(offers[0].paymentMode) == .payUpFront
        expect(offers[0].type) == .promotional
        expect(offers[0].offerIdentifier) == "com.revenuecat.monthly_4.99.1_week_intro.year_discount"
        expect(offers[0].subscriptionPeriod) == SubscriptionPeriod(value: 1, unit: .year)
        expect(offers[0].numberOfPeriods) == 1

        expect(offers[1].price) == 20.15
        expect(offers[1].priceDecimalNumber).to(beCloseTo(20.15))
        expect(offers[1].paymentMode) == .payAsYouGo
        expect(offers[1].type) == .promotional
        expect(offers[1].offerIdentifier) == "com.revenuecat.monthly_4.99.1_week_intro.pay_as_you_go"
        expect(offers[1].subscriptionPeriod) == SubscriptionPeriod(value: 1, unit: .month)
        expect(offers[1].numberOfPeriods) == 2
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
    func testSk2PriceFormatterFormatsCorrectly() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let sk2Fetcher = ProductsFetcherSK2()

        let storeProduct = try await sk2Fetcher.product(withIdentifier: Self.productID)

        let priceFormatter = try XCTUnwrap(storeProduct.priceFormatter)
        let productPrice = storeProduct.price as NSNumber

        expect(priceFormatter.string(from: productPrice)) == "$4.99"
        expect(storeProduct.localizedPriceString) == "$4.99"
    }

    @available(iOS 13.0, tvOS 13.0, macOS 10.15, watchOS 6.2, *)
    func testSk1PriceFormatterFormatsCorrectly() async throws {
        try AvailabilityChecks.iOS13APIAvailableOrSkipTest()

        let storeProduct = try await self.sk1Fetcher.product(withIdentifier: Self.productID)

        let priceFormatter = try XCTUnwrap(storeProduct.priceFormatter)
        let productPrice = storeProduct.price as NSNumber

        expect(priceFormatter.string(from: productPrice)) == "$4.99"
        expect(storeProduct.localizedPriceString) == "$4.99"
    }

    @available(iOS 13.0, tvOS 13.0, macOS 10.15, watchOS 6.2, *)
    func testSk1PriceFormatterUsesCurrentStorefront() async throws {
        try AvailabilityChecks.iOS13APIAvailableOrSkipTest()

        testSession.locale = Locale(identifier: "es_ES")
        await changeStorefront("ESP")

        var sk1Fetcher = ProductsFetcherSK1(requestTimeout: Configuration.storeKitRequestTimeoutDefault)

        var storeProduct = try await sk1Fetcher.product(withIdentifier: Self.productID)

        // This formatter would normally get locale form user preferences
        // but that's not possible to change in the tests so manually setting
        var priceFormatter = try XCTUnwrap(storeProduct.priceFormatter)
        priceFormatter.locale = Locale(identifier: "es_ES")

        var productPrice = storeProduct.price as NSNumber

        expect(priceFormatter.string(from: productPrice)) == "4,99 €"
        expect(storeProduct.currencyCode) == "EUR"

        testSession.locale = Locale(identifier: "en_EN")
        await changeStorefront("USA")

        // Note: this test passes only because the fetcher is recreated
        // therefore clearing the cache. `ProductsFetcherSK1` does not
        // detect Storefront changes to invalidate the cache like `ProductsFetcherSK2` does.
        sk1Fetcher = ProductsFetcherSK1(requestTimeout: Configuration.storeKitRequestTimeoutDefault)

        storeProduct = try await sk1Fetcher.product(withIdentifier: Self.productID)

        priceFormatter = try XCTUnwrap(storeProduct.priceFormatter)
        priceFormatter.locale = Locale(identifier: "en_US")

        productPrice = storeProduct.price as NSNumber

        expect(priceFormatter.string(from: productPrice)) == "$4.99"
        expect(storeProduct.currencyCode) == "USD"
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
    func testSk2PriceFormatterReactsToStorefrontChanges() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        testSession.locale = Locale(identifier: "es_ES")
        await changeStorefront("ESP")

        let sk2Fetcher = ProductsFetcherSK2()

        var storeProduct = try await sk2Fetcher.product(withIdentifier: Self.productID)

        // This formatter would normally get locale form user preferences
        // but that's not possible to change in the tests so manually setting
        var priceFormatter = try XCTUnwrap(storeProduct.priceFormatter)
        priceFormatter.locale = Locale(identifier: "es_ES")

        var productPrice = storeProduct.price as NSNumber

        expect(priceFormatter.string(from: productPrice)) == "4,99 €"
        expect(storeProduct.currencyCode) == "EUR"

        testSession.locale = Locale(identifier: "en_EN")
        await changeStorefront("USA")

        storeProduct = try await sk2Fetcher.product(withIdentifier: Self.productID)

        priceFormatter = try XCTUnwrap(storeProduct.priceFormatter)
        priceFormatter.locale = Locale(identifier: "en_US")

        productPrice = storeProduct.price as NSNumber

        expect(priceFormatter.string(from: productPrice)) == "$4.99"
        expect(storeProduct.currencyCode) == "USD"
    }

    func testSK1ProductTypeDoesNotCrash() async throws {
        let products = try await self.sk1Fetcher.products(withIdentifiers: [Self.productID])
        let product = try XCTUnwrap(products.first)

        // The value is undefined so we don't need to check it, just making sure this does not crash
        _ = product.productType
    }

    func testSK1ProductCategory() async throws {
        let subscription = try await self.sk1Fetcher.product(withIdentifier: Self.productID)
        let nonSubscription = try await self.sk1Fetcher.product(withIdentifier: Self.lifetimeProductID)

        expect(subscription.productCategory) == .subscription
        expect(nonSubscription.productCategory) == .nonSubscription
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
    func testSK2ProductType() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let fetcher = ProductsFetcherSK2()

        let consumable = try await fetcher.product(withIdentifier: "com.revenuecat.consumable")
        let nonConsumable = try await fetcher.product(withIdentifier: Self.lifetimeProductID)
        let nonRenewable = try await fetcher.product(withIdentifier: "com.revenuecat.non_renewable")
        let autoRenewable = try await fetcher.product(withIdentifier: Self.productID)

        expect(consumable.productType) == .consumable
        expect(nonConsumable.productType) == .nonConsumable
        expect(nonRenewable.productType) == .nonRenewableSubscription
        expect(autoRenewable.productType) == .autoRenewableSubscription
    }

    @available(iOS 15.0, tvOS 15.0, macOS 12.0, watchOS 8.0, *)
    func testSK2ProductCategory() async throws {
        try AvailabilityChecks.iOS15APIAvailableOrSkipTest()

        let fetcher = ProductsFetcherSK2()

        let subscription = try await fetcher.product(withIdentifier: Self.productID)
        let nonSubscription = try await fetcher.product(withIdentifier: Self.lifetimeProductID)

        expect(subscription.productCategory) == .subscription
        expect(nonSubscription.productCategory) == .nonSubscription
    }

}

private extension StoreProductTests {

    func expectEqualProducts(_ productA: StoreProductType, _ productB: StoreProductType) {
        expect(productA.productIdentifier) == productB.productIdentifier
        // Note: can't compare productTypes because SK1 doesn't have full information
        expect(productA.productCategory) == productB.productCategory
        expect(productA.localizedDescription) == productB.localizedDescription
        expect(productA.price) == productB.price
        expect(productA.localizedPriceString) == productB.localizedPriceString
        expect(productA.productIdentifier) == productB.productIdentifier
        expect(productA.isFamilyShareable) == productB.isFamilyShareable
        expect(productA.localizedTitle) == productB.localizedTitle

        expect(productA.isFamilyShareable) == productB.isFamilyShareable

        expect(productA.discounts) == productB.discounts

        if productA.subscriptionPeriod == nil {
            expect(productB.subscriptionPeriod).to(beNil())
        } else {
            expect(productA.subscriptionPeriod) == productB.subscriptionPeriod
        }

        if productA.introductoryDiscount == nil {
            expect(productB.introductoryDiscount).to(beNil())
        } else {
            expect(productA.introductoryDiscount) == productB.introductoryDiscount
        }

        if productA.subscriptionGroupIdentifier == nil {
            expect(productB.subscriptionGroupIdentifier).to(beNil())
        } else {
            expect(productA.subscriptionGroupIdentifier) == productB.subscriptionGroupIdentifier
        }
    }

}
