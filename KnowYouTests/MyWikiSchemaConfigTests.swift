import XCTest
@testable import KnowYou

final class MyWikiSchemaConfigTests: XCTestCase {
    func testDefaultPersonalContextSchemaKeepsOntologyCategoriesConfigurable() throws {
        let schema = try MyWikiSchemaConfig.defaultPersonalContext()

        XCTAssertEqual(schema.id, "personal-context-default")
        XCTAssertEqual(schema.categories.map(\.id), [
            "people",
            "organizations",
            "projects",
            "events",
            "topics",
            "decisions",
            "preferences",
            "follow-ups",
            "summaries",
            "sources"
        ])
        XCTAssertEqual(schema.categories.first?.displayName, "People")
        XCTAssertEqual(schema.categories.first?.directory, "wiki/people")
        XCTAssertEqual(schema.categories.first?.frontmatterTypes, ["person"])
        XCTAssertTrue(schema.categories.first?.extractionGuidance.contains("real individual people") == true)
    }

    func testRecentIsAViewNotAnOntologyCategory() throws {
        let schema = try MyWikiSchemaConfig.defaultPersonalContext()

        XCTAssertFalse(schema.categories.map(\.id).contains("recent"))
        XCTAssertTrue(schema.views.contains { view in
            view.id == "recent" && view.kind == .recentActivity
        })
    }

    func testDecodesSchemaWithLegacyDirectoriesAndTypesDefaults() throws {
        let json = """
        {
          "id": "custom",
          "displayName": "Custom",
          "categories": [
            {
              "id": "relationships",
              "displayName": "Relationships",
              "singularName": "Relationship",
              "directory": "wiki/relationships",
              "frontmatterTypes": ["relationship"],
              "extractionGuidance": "Relationships between people and projects.",
              "detailSections": ["Summary", "Sources"]
            }
          ],
          "views": []
        }
        """.data(using: .utf8)!

        let schema = try JSONDecoder().decode(MyWikiSchemaConfig.self, from: json)

        XCTAssertEqual(schema.categories.first?.legacyDirectories, [])
        XCTAssertEqual(schema.categories.first?.legacyTypes, [])
    }
}
