import XCTest
@testable import RelayCore

final class SiteControlsTests: XCTestCase {

    private func browserTarget(_ url: String, title: String = "", bundle: String = "com.google.Chrome") -> SiteTarget {
        SiteTarget(url: url, title: title, bundleID: bundle, isBrowser: true)
    }

    private func rule(_ id: String, hosts: [String], pathPrefix: String? = nil, enabled: Bool = true,
                      buttons: [SiteButton] = [SiteButton(id: "ask", title: "Ask", effect: .prompt(.explain))]) -> SiteRule {
        SiteRule(id: id, name: id, enabled: enabled, scope: SiteScope(kind: .browser),
                 hosts: hosts, pathPrefix: pathPrefix, buttons: buttons)
    }

    // MARK: - Starters

    func testStarterRulesAreValidAndUnique() {
        XCTAssertFalse(SiteRule.starters.isEmpty)
        XCTAssertEqual(Set(SiteRule.starters.map(\.id)).count, SiteRule.starters.count)
        for rule in SiteRule.starters {
            XCTAssertNoThrow(try rule.validate(), rule.id)
            XCTAssertFalse(rule.buttons.isEmpty, rule.id)
        }
    }

    func testStartersShipNoBareKeystroke() {
        // A modifier-free starter button could type a stray character into a
        // focused text field, so the library deliberately ships none.
        for rule in SiteRule.starters {
            for button in rule.buttons {
                if case .keystroke(_, let modifiers) = button.effect {
                    XCTAssertFalse(modifiers.isEmpty, "\(rule.id)/\(button.id)")
                }
            }
        }
    }

    func testStarterRulesNeverBindEditingOrSensitiveQuickActions() {
        for rule in SiteRule.starters {
            for button in rule.buttons {
                if case .quickAction = button.effect { XCTFail("Starters must not run shell commands: \(rule.id)") }
                if case .pluginCommand = button.effect { XCTFail("Starters must not run plugins: \(rule.id)") }
            }
        }
    }

    func testEveryStarterButtonStaysInsideTheWidthBudget() {
        for rule in SiteRule.starters {
            for button in rule.buttons {
                let width = SiteControlsPolicy.width(for: button)
                XCTAssertGreaterThanOrEqual(width, SiteControlsPolicy.minimumButtonWidth)
                XCTAssertLessThanOrEqual(width, SiteControlsPolicy.maximumButtonWidth)
            }
        }
    }

    // MARK: - Matching

    func testExactHostMatch() {
        let detection = SiteRuleMatcher.detect(target: browserTarget("https://mail.google.com/mail/u/0/#inbox"),
                                               rules: SiteRule.starters)
        XCTAssertEqual(detection.ruleID, "gmail")
        XCTAssertEqual(detection, .matched(SiteMatch(ruleID: "gmail", ruleName: "Gmail", basis: .host)))
    }

    func testWildcardMatchesApexAndSubdomain() {
        let rules = [rule("so", hosts: ["*.stackexchange.com"])]
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://stackexchange.com/questions"), rules: rules).ruleID, "so")
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://meta.stackexchange.com/questions"), rules: rules).ruleID, "so")
    }

    func testWildcardDoesNotMatchLookalikeSuffixDomain() {
        let rules = [rule("so", hosts: ["*.stackexchange.com"])]
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://evilstackexchange.com/"), rules: rules), .none)
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://stackexchange.com.evil.test/"), rules: rules), .none)
    }

    func testExactHostBeatsWildcardEvenWhenWildcardIsDeclaredFirst() {
        let rules = [rule("wild", hosts: ["*.example.com"]), rule("exact", hosts: ["docs.example.com"])]
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://docs.example.com/x"), rules: rules).ruleID, "exact")
    }

    func testLongerPathPrefixWins() {
        let rules = [rule("root", hosts: ["example.com"]), rule("deep", hosts: ["example.com"], pathPrefix: "/app/settings")]
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/app/settings/profile"), rules: rules).ruleID, "deep")
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/other"), rules: rules).ruleID, "root")
    }

    func testPathPrefixMatchesWholeSegmentsOnly() {
        let rules = [rule("app", hosts: ["example.com"], pathPrefix: "/app")]
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/app"), rules: rules).ruleID, "app")
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/app/x"), rules: rules).ruleID, "app")
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/application"), rules: rules), .none)
    }

    func testTitleMatchIsCaseInsensitiveAndOptional() {
        var withTitle = rule("docs", hosts: ["example.com"])
        withTitle.titleContains = "release notes"
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/x", title: "Release Notes v2"), rules: [withTitle]).ruleID, "docs")
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/x", title: "Something else"), rules: [withTitle]), .none)
    }

    func testEquallySpecificDistinctRulesFailClosed() {
        let rules = [rule("a", hosts: ["example.com"]), rule("b", hosts: ["example.com"])]
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/"), rules: rules), .ambiguous(["a", "b"]))
    }

    func testSameRuleRepeatedAtDifferentSpecificityIsNotAmbiguous() {
        let rules = [rule("root", hosts: ["example.com"]),
                     rule("sub", hosts: ["*.example.com"]),
                     rule("deep", hosts: ["example.com"], pathPrefix: "/a/b")]
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://a.example.com/a/b/c"), rules: rules).ruleID, "deep")
    }

    func testDisabledRuleIsIgnored() {
        let rules = [rule("off", hosts: ["example.com"], enabled: false)]
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/"), rules: rules), .none)
    }

    func testInvalidRuleIsInertInsteadOfThrowing() {
        let rules = [rule("bad", hosts: ["UPPER CASE HOST"]), rule("ok", hosts: ["example.com"])]
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/"), rules: rules).ruleID, "ok")
    }

    func testBrowserRuleNeverMatchesDesktopApplication() {
        let target = SiteTarget(url: "", title: "Claude", bundleID: "com.anthropic.claudefordesktop", isBrowser: false)
        XCTAssertEqual(SiteRuleMatcher.detect(target: target, rules: [rule("web", hosts: ["claude.ai"])]), .none)
    }

    func testDesktopRuleMatchesOnlyItsOwnBundle() {
        let target = SiteTarget(url: "", title: "Claude", bundleID: "com.anthropic.claudefordesktop", isBrowser: false)
        XCTAssertEqual(SiteRuleMatcher.detect(target: target, rules: SiteRule.starters)?.ruleID, "claude-desktop")
        let chatgpt = SiteTarget(url: "", title: "ChatGPT", bundleID: "com.openai.chat", isBrowser: false)
        XCTAssertEqual(SiteRuleMatcher.detect(target: chatgpt, rules: SiteRule.starters)?.ruleID, "chatgpt-desktop")
    }

    func testBrowserRuleCanBeScopedToNamedBundles() {
        var scoped = rule("brave-only", hosts: ["example.com"])
        scoped.scope = SiteScope(kind: .browser, bundles: ["com.brave.Browser"])
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/", bundle: "com.google.Chrome"), rules: [scoped]), .none)
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/", bundle: "com.brave.Browser"), rules: [scoped]).ruleID, "brave-only")
    }

    func testPageIdentityRefusesNonHTTPSAndCredentialURLs() {
        XCTAssertNil(SitePageIdentity.parse("http://example.com/"))
        XCTAssertNil(SitePageIdentity.parse("https://user:secret@example.com/"))
        XCTAssertNil(SitePageIdentity.parse("https://example.com:8443/"))
        XCTAssertNil(SitePageIdentity.parse("file:///etc/passwd"))
        XCTAssertNil(SitePageIdentity.parse("https://example.com/#fragment"))
        XCTAssertNotNil(SitePageIdentity.parse("https://example.com/a?b=c"))
    }

    func testBrowserTargetWithoutIdentifiablePageIsReportedUnavailable() {
        let detection = SiteRuleMatcher.detect(target: browserTarget("about:blank"), rules: SiteRule.starters)
        guard case .unavailable(let reason) = detection else { return XCTFail("expected unavailable") }
        XCTAssertFalse(reason.isEmpty)
    }

    func testNoMatchingRuleReportsNoneRatherThanAGuess() {
        XCTAssertEqual(SiteRuleMatcher.detect(target: browserTarget("https://example.com/"), rules: SiteRule.starters), .none)
    }

    // MARK: - Templates

    func testTemplateRendersEveryKnownPlaceholder() throws {
        let context = SiteTemplateContext(url: "https://docs.example.com/a/b?q=1", title: "Title",
                                          selection: "picked", bundleID: "com.google.Chrome")
        let rendered = try SiteTemplate.render("{host}|{path}|{query}|{title}|{selection}|{bundle}", context: context)
        XCTAssertEqual(rendered, "docs.example.com|/a/b|q=1|Title|picked|com.google.Chrome")
    }

    func testTemplateRefusesUnknownPlaceholder() {
        XCTAssertThrowsError(try SiteTemplate.render("{nope}", context: SiteTemplateContext())) { error in
            XCTAssertTrue(error.localizedDescription.contains("{nope}"))
        }
        XCTAssertThrowsError(try SiteTemplate.render("{url", context: SiteTemplateContext())) { _ in }
    }

    func testTemplateStripsControlCharacters() throws {
        let context = SiteTemplateContext(url: "https://example.com/", title: "line\u{0}break\nnext")
        let rendered = try SiteTemplate.render("{title}", context: context)
        XCTAssertFalse(rendered.contains("\u{0}"))
        XCTAssertEqual(rendered, "linebreaknext")
    }

    func testTemplateDetectsSelectionRequirement() {
        XCTAssertTrue(SiteTemplate.requiresSelection("https://x.test/?q={selection}"))
        XCTAssertFalse(SiteTemplate.requiresSelection("https://x.test/"))
    }

    // MARK: - Button and rule validation

    func testKeystrokeAllowlistRejectsUnknownKey() {
        let button = SiteButton(id: "k", title: "Key", effect: .keystroke(key: "volumeUp", modifiers: ["command"]))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(button: button, ruleID: "r"))
    }

    func testKeystrokeBindingCannotQuitAnApplication() {
        for combo in [["command"], ["command", "shift"], ["command", "control"]] {
            let button = SiteButton(id: "q", title: "Quit", effect: .keystroke(key: "q", modifiers: combo))
            XCTAssertThrowsError(try SiteControlsPolicy.validate(button: button, ruleID: "r"), combo.joined(separator: "+"))
        }
        let escape = SiteButton(id: "es", title: "Force", effect: .keystroke(key: "escape", modifiers: ["command", "option"]))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(button: escape, ruleID: "r"))
    }

    func testModifierNamesAreValidatedAndDeduplicated() {
        let good = SiteButton(id: "b", title: "Bold", effect: .keystroke(key: "b", modifiers: ["command"]))
        XCTAssertNoThrow(try SiteControlsPolicy.validate(button: good, ruleID: "r"))
        let bad = SiteButton(id: "b", title: "Bold", effect: .keystroke(key: "b", modifiers: ["cmd"]))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(button: bad, ruleID: "r"))
        let repeated = SiteButton(id: "b", title: "Bold", effect: .keystroke(key: "b", modifiers: ["command", "command"]))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(button: repeated, ruleID: "r"))
    }

    func testOpenURLRejectsDangerousSchemes() {
        for template in ["javascript:alert(1)", "data:text/html,x", "file:///etc/passwd", "http://plain.test/"] {
            let button = SiteButton(id: "u", title: "URL", effect: .openURL(template: template))
            XCTAssertThrowsError(try SiteControlsPolicy.validate(button: button, ruleID: "r"), template)
        }
        let ok = SiteButton(id: "u", title: "URL", effect: .openURL(template: "https://x.test/?q={selection}"))
        XCTAssertNoThrow(try SiteControlsPolicy.validate(button: ok, ruleID: "r"))
    }

    func testPluginCommandRejectsPathTraversal() {
        let button = SiteButton(id: "p", title: "Plugin", effect: .pluginCommand(plugin: "../etc", command: "run"))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(button: button, ruleID: "r"))
    }

    func testRelayEffectCannotOpenTheScreenshotViewer() {
        let button = SiteButton(id: "r", title: "Viewer", effect: .relay(page: .screenshots))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(button: button, ruleID: "r"))
        let ok = SiteButton(id: "r", title: "Capture", effect: .relay(page: .capture))
        XCTAssertNoThrow(try SiteControlsPolicy.validate(button: ok, ruleID: "r"))
    }

    func testRuleRequiresHostsForBrowserScopeAndBundlesForAppScope() {
        let noHosts = SiteRule(id: "a", name: "A", scope: SiteScope(kind: .browser), hosts: [], buttons: [
            SiteButton(id: "x", title: "X", effect: .prompt(.explain))
        ])
        XCTAssertThrowsError(try noHosts.validate())
        let noBundles = SiteRule(id: "b", name: "B", scope: SiteScope(kind: .apps, bundles: []), buttons: [
            SiteButton(id: "x", title: "X", effect: .prompt(.explain))
        ])
        XCTAssertThrowsError(try noBundles.validate())
    }

    func testRuleLimitsButtonsAndRejectsRepeats() {
        let many = SiteRule(id: "a", name: "A", scope: SiteScope(kind: .browser), hosts: ["example.com"],
                            buttons: (0...SiteControlsPolicy.maximumButtons).map {
                                SiteButton(id: "b\($0)", title: "B", effect: .prompt(.explain))
                            })
        XCTAssertThrowsError(try many.validate())
        let repeated = SiteRule(id: "a", name: "A", scope: SiteScope(kind: .browser), hosts: ["example.com"],
                                buttons: [SiteButton(id: "same", title: "One", effect: .prompt(.explain)),
                                          SiteButton(id: "same", title: "Two", effect: .prompt(.explain))])
        XCTAssertThrowsError(try repeated.validate())
    }

    func testButtonWidthOutsideTheBudgetIsRejected() {
        let wide = SiteButton(id: "w", title: "Wide", width: SiteControlsPolicy.maximumButtonWidth + 1, effect: .prompt(.explain))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(button: wide, ruleID: "r"))
        let narrow = SiteButton(id: "n", title: "Narrow", width: 1, effect: .prompt(.explain))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(button: narrow, ruleID: "r"))
    }

    func testHostValidationRejectsWildcardsInTheMiddle() {
        XCTAssertThrowsError(try SiteControlsPolicy.validate(host: "a.*.example.com"))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(host: "UPPER.example.com"))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(host: "example..com"))
        XCTAssertThrowsError(try SiteControlsPolicy.validate(host: ""))
        XCTAssertNoThrow(try SiteControlsPolicy.validate(host: "*.example.com"))
        XCTAssertNoThrow(try SiteControlsPolicy.validate(host: "mail.google.com"))
    }

    // MARK: - Presentation policy

    func testInlineAndOverflowSplitKeepsEveryButtonReachable() {
        var sample = rule("s", hosts: ["example.com"])
        sample.buttons = (0..<7).map { SiteButton(id: "b\($0)", title: "B\($0)", effect: .prompt(.explain)) }
        XCTAssertEqual(SiteControlsPolicy.inlineButtons(sample.buttons).count, SiteControlsPolicy.inlineLimit)
        let overflow = SiteControlsPolicy.overflowButtons(sample.buttons)
        XCTAssertEqual(overflow.count, 7 - SiteControlsPolicy.inlineLimit)
        XCTAssertEqual(SiteControlsPolicy.inlineButtons(sample.buttons) + overflow, sample.buttons)
    }

    func testPagesCoverEveryOverflowButtonExactlyOnce() {
        let buttons = (0..<10).map { SiteButton(id: "b\($0)", title: "B\($0)", effect: .prompt(.explain)) }
        let pages = SiteControlsPolicy.pageCount(buttons.count)
        let collected = (0..<pages).flatMap { SiteControlsPolicy.page(buttons, index: $0) }
        XCTAssertEqual(collected, buttons)
        XCTAssertTrue(SiteControlsPolicy.page(buttons, index: pages).isEmpty)
        XCTAssertTrue(SiteControlsPolicy.page(buttons, index: -1).isEmpty)
    }

    func testEmptyButtonListStillCountsAsOnePage() {
        XCTAssertEqual(SiteControlsPolicy.pageCount(0), 1)
        XCTAssertEqual(SiteControlsPolicy.pageCount(-3), 1)
    }

    func testDisplayTitleTruncatesAndAddsTheIcon() {
        let long = SiteButton(id: "l", title: String(repeating: "x", count: 60), icon: "📥", effect: .prompt(.explain))
        let shown = SiteControlsPolicy.displayTitle(long)
        XCTAssertLessThanOrEqual(shown.count, SiteControlsPolicy.maximumTitle + 2)
        XCTAssertTrue(shown.hasPrefix("📥 "))
    }

    // MARK: - Configuration integration

    func testConfigurationRoundTripsSiteRules() throws {
        var configuration = AppConfiguration()
        configuration.siteRules = SiteRule.starters
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)
        XCTAssertEqual(decoded.siteRules, SiteRule.starters)
        XCTAssertNoThrow(try decoded.validate())
    }

    func testConfigurationWithoutSiteRulesKeepsLoadingAndSeedsStarters() throws {
        var configuration = AppConfiguration()
        configuration.siteRules = []
        let data = try JSONEncoder().encode(configuration)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "siteRules")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: stripped)
        XCTAssertEqual(decoded.siteRules, SiteRule.starters)
    }

    func testAnIntentionallyEmptyRuleListIsPreserved() throws {
        var configuration = AppConfiguration()
        configuration.siteRules = []
        let data = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(AppConfiguration.self, from: data)
        XCTAssertTrue(decoded.siteRules.isEmpty)
        XCTAssertNoThrow(try decoded.validate())
    }

    func testConfigurationRejectsDuplicateRuleIdentifiers() {
        var configuration = AppConfiguration()
        configuration.siteRules = [SiteRule.gmail, SiteRule.gmail]
        XCTAssertThrowsError(try configuration.validate())
    }

    func testConfigurationRejectsTooManyRules() {
        var configuration = AppConfiguration()
        configuration.siteRules = (0...SiteControlsPolicy.maximumRules).map {
            rule("r\($0)", hosts: ["example\($0).com"])
        }
        XCTAssertThrowsError(try configuration.validate())
    }
}
