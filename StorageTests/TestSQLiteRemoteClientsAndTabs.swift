/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import XCTest

public class MockRemoteClientsAndTabs: RemoteClientsAndTabs {
    public let clientsAndTabs: [ClientAndTabs]

    public init() {
        let now = NSDate.now()
        let client1GUID = Bytes.generateGUID()
        let client2GUID = Bytes.generateGUID()
        let u11 = NSURL(string: "http://test.com/test1")!
        let tab11 = RemoteTab(clientGUID: client1GUID, URL: u11, title: "Test 1", history: [    ], lastUsed: (now - OneMinuteInMilliseconds), icon: nil)

        let u12 = NSURL(string: "http://test.com/test2")!
        let tab12 = RemoteTab(clientGUID: client1GUID, URL: u12, title: "Test 2", history: [], lastUsed: (now - OneHourInMilliseconds), icon: nil)

        let tab21 = RemoteTab(clientGUID: client2GUID, URL: u11, title: "Test 1", history: [], lastUsed: (now - OneDayInMilliseconds), icon: nil)

        let u22 = NSURL(string: "http://different.com/test2")!
        let tab22 = RemoteTab(clientGUID: client2GUID, URL: u22, title: "Different Test 2", history: [], lastUsed: now + OneHourInMilliseconds, icon: nil)

        let client1 = RemoteClient(guid: client1GUID, name: "Test client 1", modified: (now - OneMinuteInMilliseconds), type: "mobile", formfactor: "largetablet", os: "iOS")
        let client2 = RemoteClient(guid: client2GUID, name: "Test client 2", modified: (now - OneHourInMilliseconds), type: "desktop", formfactor: "laptop", os: "Darwin")

        let localClient = RemoteClient(guid: nil, name: "Test local client", modified: (now - OneMinuteInMilliseconds), type: "mobile", formfactor: "largetablet", os: "iOS")
        let localUrl1 = NSURL(string: "http://test.com/testlocal1")!
        let localTab1 = RemoteTab(clientGUID: nil, URL: localUrl1, title: "Local test 1", history: [], lastUsed: (now - OneMinuteInMilliseconds), icon: nil)
        let localUrl2 = NSURL(string: "http://test.com/testlocal2")!
        let localTab2 = RemoteTab(clientGUID: nil, URL: localUrl2, title: "Local test 2", history: [], lastUsed: (now - OneMinuteInMilliseconds), icon: nil)

        // Tabs are ordered most-recent-first.
        self.clientsAndTabs = [ClientAndTabs(client: client1, tabs: [tab11, tab12]),
                               ClientAndTabs(client: client2, tabs: [tab22, tab21]),
                               ClientAndTabs(client: localClient, tabs: [localTab1, localTab2])]
    }

    public func onRemovedAccount() -> Success {
        return succeed()
    }

    public func wipeClients() -> Success {
        return succeed()
    }

    public func wipeRemoteTabs() -> Deferred<Result<()>> {
        return succeed()
    }

    public func wipeTabs() -> Success {
        return succeed()
    }

    public func insertOrUpdateClients(clients: [RemoteClient]) -> Success {
        return succeed()
    }

    public func insertOrUpdateClient(client: RemoteClient) -> Success {
        return succeed()
    }

    public func insertOrUpdateTabs(tabs: [RemoteTab]) -> Deferred<Result<Int>> {
        return insertOrUpdateTabsForClientGUID(nil, tabs: [RemoteTab]())
    }

    public func insertOrUpdateTabsForClientGUID(clientGUID: String?, tabs: [RemoteTab]) -> Deferred<Result<Int>> {
        return deferResult(-1)
    }

    public func getClientsAndTabs() -> Deferred<Result<[ClientAndTabs]>> {
        return deferResult(self.clientsAndTabs)
    }

    public func getClients() -> Deferred<Result<[RemoteClient]>> {
        return deferResult(self.clientsAndTabs.map { $0.client })
    }

    public func getTabsForClientWithGUID(guid: GUID?) -> Deferred<Result<[RemoteTab]>> {
        return deferResult(optFilter(self.clientsAndTabs.map { $0.client.guid == guid ? $0.tabs : nil })[0])
    }

    public func deleteCommands() -> Success { return succeed() }
    public func deleteCommands(clientGUID: GUID) -> Success { return succeed() }

    public func getCommands() -> Deferred<Result<[GUID: [SyncCommand]]>>  { return deferResult([GUID: [SyncCommand]]()) }

    public func insertCommand(command: SyncCommand, forClients clients: [RemoteClient]) -> Deferred<Result<Int>>  { return deferResult(0) }
    public func insertCommands(commands: [SyncCommand], forClients clients: [RemoteClient]) -> Deferred<Result<Int>>  { return deferResult(0) }
}

func removeLocalClient(a: ClientAndTabs) -> Bool {
    return a.client.guid != nil
}

func byGUID(a: ClientAndTabs, b: ClientAndTabs) -> Bool {
    return a.client.guid < b.client.guid
}

func byURL(a: RemoteTab, b: RemoteTab) -> Bool {
    return a.URL.absoluteString < b.URL.absoluteString
}

class SQLRemoteClientsAndTabsTests: XCTestCase {
    var clientsAndTabs: SQLiteRemoteClientsAndTabs!

    lazy var clients: [ClientAndTabs] = MockRemoteClientsAndTabs().clientsAndTabs

    override func setUp() {
        let files = MockFiles()
        files.remove("browser.db")
        clientsAndTabs = SQLiteRemoteClientsAndTabs(db: BrowserDB(filename: "browser.db", files: files))
    }


    func testInsertGetClear() {
        // Insert some test data.
        for c in clients {
            let e = self.expectationWithDescription("Insert.")
            clientsAndTabs.insertOrUpdateClient(c.client).upon {
                XCTAssertTrue($0.isSuccess)
                e.fulfill()
            }
            clientsAndTabs.insertOrUpdateTabsForClientGUID(c.client.guid, tabs: c.tabs)
        }

        let f = self.expectationWithDescription("Get after insert.")
        clientsAndTabs.getClientsAndTabs().upon {
            if let got = $0.successValue {
                let expected = self.clients.sorted(byGUID).filter(removeLocalClient)
                let actual = got.sorted(byGUID)

                // This comparison will fail if the order of the tabs changes. We sort the result
                // as part of the DB query, so it's not actively sorted in Swift.
                XCTAssertEqual(expected, actual)
            } else {
                XCTFail("Expected clients!")
            }
            f.fulfill()
        }

        // Update the test data with a client with new tabs, and one with no tabs.
        let client0NewTabs = clients[1].tabs.map { $0.withClientGUID(self.clients[0].client.guid) }
        let client1NewTabs: [RemoteTab] = []
        let expected = [
            ClientAndTabs(client: clients[0].client, tabs: client0NewTabs),
            ClientAndTabs(client: clients[1].client, tabs: client1NewTabs),
        ].sorted(byGUID)

        func doUpdate(guid: String?, tabs: [RemoteTab]) {
            let g0 = self.expectationWithDescription("Update client \(guid).")
            clientsAndTabs.insertOrUpdateTabsForClientGUID(guid, tabs: tabs).upon {
                if let rowID = $0.successValue {
                    XCTAssertTrue(rowID > -1)
                } else {
                    XCTFail("Didn't successfully update.")
                }
                g0.fulfill()
            }
        }

        doUpdate(clients[0].client.guid, client0NewTabs)
        doUpdate(clients[1].client.guid, client1NewTabs)
        // Also update the local tabs list. It should still not appear in the expected tabs below.
        doUpdate(clients[2].client.guid, client1NewTabs)

        let h = self.expectationWithDescription("Get after update.")
        clientsAndTabs.getClientsAndTabs().upon {
            if let clients = $0.successValue {
                XCTAssertEqual(expected, clients.sorted(byGUID))
            } else {
                XCTFail("Expected clients!")
            }
            h.fulfill()
        }

        // Now clear everything, and verify we have no clients or tabs whatsoever.
        let i = self.expectationWithDescription("Clear.")
        clientsAndTabs.clear().upon {
            XCTAssertTrue($0.isSuccess)
            i.fulfill()
        }

        let j = self.expectationWithDescription("Get after clear.")
        clientsAndTabs.getClientsAndTabs().upon {
            if let clients = $0.successValue {
                XCTAssertEqual(0, clients.count)
            } else {
                XCTFail("Expected clients!")
            }
            j.fulfill()
        }

        self.waitForExpectationsWithTimeout(10, handler: nil)
    }

    func testGetTabsForClient() {
        for c in clients {
            let e = self.expectationWithDescription("Insert.")
            clientsAndTabs.insertOrUpdateClient(c.client).upon {
                XCTAssertTrue($0.isSuccess)
                e.fulfill()
            }
            clientsAndTabs.insertOrUpdateTabsForClientGUID(c.client.guid, tabs: c.tabs)
        }


        let e = self.expectationWithDescription("Get after insert.")
        let ct = clients[0]
        clientsAndTabs.getTabsForClientWithGUID(ct.client.guid).upon {
            if let got = $0.successValue {
                // This comparison will fail if the order of the tabs changes. We sort the result
                // as part of the DB query, so it's not actively sorted in Swift.
                XCTAssertEqual(ct.tabs.count, got.count)
                XCTAssertEqual(ct.tabs.sorted(byURL), got.sorted(byURL))
            } else {
                XCTFail("Expected tabs!")
            }
            e.fulfill()
        }

        let f = self.expectationWithDescription("Get after insert.")
        let localClient = clients[0]
        clientsAndTabs.getTabsForClientWithGUID(localClient.client.guid).upon {
            if let got = $0.successValue {
                // This comparison will fail if the order of the tabs changes. We sort the result
                // as part of the DB query, so it's not actively sorted in Swift.
                XCTAssertEqual(localClient.tabs.count, got.count)
                XCTAssertEqual(localClient.tabs.sorted(byURL), got.sorted(byURL))
            } else {
                XCTFail("Expected tabs!")
            }
            f.fulfill()
        }

        self.waitForExpectationsWithTimeout(10, handler: nil)
    }
}
