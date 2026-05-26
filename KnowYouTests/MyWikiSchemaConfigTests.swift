import XCTest
@testable import KnowYou

final class MyWikiSchemaConfigTests: XCTestCase {
    func testDefaultPersonalContextSchemaKeepsOntologyCategoriesConfigurable() throws {
        let schema = try MyWikiSchemaConfig.defaultPersonalContext()

        XCTAssertEqual(schema.id, "personal-context-default")
        XCTAssertEqual(schema.categories.map(\.id), [
            "sources",
            "entities",
            "concepts"
        ])
        XCTAssertEqual(schema.categories.map(\.directory), [
            "wiki/sources",
            "wiki/entities",
            "wiki/concepts"
        ])
        XCTAssertEqual(schema.categories.map { $0.frontmatterTypes.first }, [
            "source",
            "entity",
            "concept"
        ])
        XCTAssertEqual(schema.categories.first(where: { $0.id == "entities" })?.legacyDirectories, [
            "wiki/people",
            "wiki/organizations",
            "wiki/projects",
            "wiki/events"
        ])
        XCTAssertEqual(schema.categories.first(where: { $0.id == "concepts" })?.legacyDirectories, [
            "wiki/topics",
            "wiki/decisions",
            "wiki/preferences",
            "wiki/follow-ups",
            "wiki/summaries"
        ])
        XCTAssertEqual(schema.categories.first?.displayName, "Sources")
        XCTAssertTrue(schema.categories.first?.extractionGuidance.contains("KnowYou diary") == true)
        XCTAssertTrue(schema.categories.first(where: { $0.id == "entities" })?.extractionGuidance.contains("person, project, organization, other") == true)
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
