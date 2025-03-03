//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  LockTests.swift
//
//  Created by Nacho Soto on 2/20/22.

import Nimble
import XCTest

@testable import RevenueCat

class LockTests: TestCase {

    func testClosureIsCalled() {
        let lock = Lock()

        var called = false
        lock.perform { called = true }
        expect(called) == true
    }

    func testLockIsReentrant() {
        let lock = Lock()

        var called = false
        lock.perform {
            lock.perform { called = true }
        }
        expect(called) == true
    }

}
