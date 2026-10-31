import Foundation
import CorkCore

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: Bool, file: String = #fileID, line: Int = #line) throws {
    guard condition else { throw CheckFailure(description: "\(file):\(line): expectation failed") }
}

func expectThrows<T>(_ body: () throws -> T) throws {
    do { _ = try body() }
    catch is CorkError { return }
    throw CheckFailure(description: "Expected a CorkError")
}

@MainActor func expectThrowsAsync<T>(_ body: () async throws -> T) async throws {
    do { _ = try await body() }
    catch is CorkError { return }
    throw CheckFailure(description: "Expected a CorkError")
}

@main enum CorkChecks {
    @MainActor static func main() async {
        let cases: [(String, @MainActor () async throws -> Void)] = [
            ("Favourite restores scene and keeps global preferences", favouritesRestoreSceneAndPreserveGlobalPreferences),
            ("Favourite persistence, recovery and media reuse", favouritesPersistRecoverAndReuseMedia),
            ("Schedule defaults, intervals, validation and persistence", randomizationSchedulesValidatePersistAndCalculate),
            ("Local calendar schedules handle DST", calendarSchedulesHandleLocalTimeAndDST),
            ("Schedule driver defers, catches up once and cancels", scheduleDriverDefersCatchesUpOnceAndCancels),
            ("Large library rolls remain bounded and source diverse", largeLibraryRemainsSeededAndSourceDiverse),
            ("Atomic batch updates", batchEditIsAtomicAndRejectsStaleIdentity),
            ("Aspect-preserving resize and restyle", resizingPreservesRatioAndStyleChangesRecomputeDecoration),
            ("Notes, round-trip and style boundaries", notesRoundTripAndCannotBecomeImageTreatments),
            ("Rotated layouts fit safe areas", allLayoutsFitRotatedPrintsInsideTheSafeArea),
            ("Selected-item layout", selectionLayoutLeavesOtherDisplaysUntouched),
            ("Geometry and asset validation", invalidAssetsAndUnboundedGeometryAreRejected),
            ("Undo and redo", undoRedoKeepsStableItemsAndBoundsHistory),
            ("Atomic persistence and corruption recovery", persistenceRecoversThePreviousCompleteBoard),
            ("Image input validation", imageImportRejectsRelativeAndNonImageFiles),
            ("MCP lifecycle and errors", mcpLifecycleNotificationsAndToolErrors),
            ("Private local socket round-trip", localSocketRoundTripAndPermissions),
            ("Strict MCP argument schemas", strictToolArgumentValidation),
            ("Old board migration preserves images and layout", legacyBoardMigrationPreservesTheWall),
            ("Desktop and wallpaper settings restore", wallpaperSettingsSurviveSaveAndReload),
            ("Wallpaper import owns its local copy", wallpaperImportOwnsItsCopy),
            ("Desktop and login MCP schemas", desktopToolSchemasRejectAmbiguousInputs),
            ("Coherent, mixed, caption-free rotation", rotationIsCoherentMixedAndCaptionFree),
            ("Rotation preserves notes, displays and undo", rotationPreservesNotesOtherDisplaysAndUndo),
            ("Rotation avoids repeats and rejects bad metadata", rotationAvoidsPreviousMoodAndAvailablePhotos),
            ("Collection import, merge, ownership and recovery", collectionImportOwnsMediaAndMergesMetadataAtomically),
            ("Desktop controls migration, shortcut validation and persistence", desktopControlSettingsMigrateAndPersist),
            ("Anchored third-finger swipe fires once", anchoredThirdFingerSwipeFiresOnce),
            ("Anchored swipe rejects scrolling and ordinary gestures", anchoredSwipeRejectsNormalGestures),
            ("Anchored swipe resets invalid input and device changes", anchoredSwipeResetsInvalidAndDisconnectedInput),
            ("Greedy layout fills major rectangles and preserves prints", greedyLayoutFillsLargeHolesAndPreservesIdentity),
            ("Greedy layout preserves notes and other displays", greedyLayoutPreservesObstaclesAndRejectsImpossibleSpace),
            ("Greedy rotation matches aspect ratios and fills free space", greedyRotationMatchesAspectsWithoutLargeEmptyRectangles),
            ("Visual moods mix source boards and subjects", rotationMixesBoardsWithinOneVisualMood),
            ("Greedy layout handles overlapping and offscreen notes", greedyLayoutHandlesOverlappingAndOffscreenNotes),
            ("Scenes match colours and select native-resolution wallpapers", sceneColoursRankCompatibleImagesAndChooseNativeWallpaper),
            ("Fill Empty and kept-image preservation", fillEmptyPreservesEveryExistingItemAndKeptImagesSurviveRoll),
            ("Hidden widget area is available to Fill Empty", hidingWidgetsMakesTheirAreaAvailableToFill),
            ("Scene and randomize shortcut settings migrate and persist", scenePreferencesAndRandomizeShortcutMigrateAndPersist),
            ("Local colour analysis uses actual pixels", colourAnalysisFindsRealImageColoursDeterministically),
            ("Wallpaper ownership, metadata merge, rollback and recovery", wallpaperCollectionOwnsLargeMediaAndRollsBackFailedImports),
            ("Note layout choice migration, persistence and validation", noteLayoutChoiceMigratesPersistsAndValidates),
            ("Overlay notes release layout space and stay in place", overlayNotesReleaseSpaceWithoutMovingOrDeletingNotes),
            ("Overlay notes stay above newer photos", overlayNotesStayAboveNewerPhotosAndKeepTheirOwnOrder),
            ("Blue photo walls reject pink-purple backgrounds", wallpaperMatchingRejectsPinkPurpleForDominantlyBluePhotos),
            ("Wallpaper matching checks the selected photos, not just the preset", sceneWallpaperUsesActualPhotoHueEvenWithABroadPreset),
            ("Paired palettes migrate, validate and persist", pairedPalettesMigrateValidateAndPersist),
            ("Paired rolls balance visible colour area and source boards", pairedRollsBalanceVisibleAreaAndKeepBoardVariety),
            ("Paired backgrounds match a real colour family", pairedWallpapersUseAnActualFamilyAndRejectUnrelatedPink),
            ("Paired Fill Empty preserves placed images and notes", pairedFillBalancesAroundKeptImagesWithoutMovingThem),
            ("Measured colour classification distinguishes strong colours and accents", colourClassificationMeasuresStrongAndWeakPixelCoverage),
            ("Any two colour families migrate, validate and persist", arbitraryColourPairsAndStrengthMigrateValidateAndPersist),
            ("Custom colours search all moods and balance measured area", customColoursSearchAllMoodsAndBalanceActualColourArea),
            ("Custom colour Fill Empty keeps anchors and undo", customColourFillPreservesAnchorsNotesAndUndo),
            ("Custom wallpaper checks measured families and native pixels", customWallpaperMatchingUsesMeasuredFamiliesAndNativeDimensions),
            ("Colour cache backfill preserves metadata and media", colourCacheBackfillsAtomicallyAndReusesAllMedia),
            ("Coordinate edits anchor and reflow existing photos", coordinateEditsAnchorItemsAndReflowTheSamePhotos),
            ("Overlay and no-op coordinate edits preserve the wall", overlayMovesAndUnchangedCoordinatesDoNotReflowPhotos),
            ("Individual visibility reflows without losing items", hiddenItemsReleaseSpaceAndSurviveRollsAndUndo),
            ("Display growth fills and shrinkage refits", displayChangesFillMoreSpaceAndRefitSmallerCanvases),
            ("Automatic note colours preserve manual choices", automaticNotePaperMatchesPhotosAndRetainsTheManualColour),
            ("Widget registration owns and preserves resources", widgetRegistrationOwnsResourcesAndPersistsMetadata),
            ("Widget package traversal and symlinks are rejected", widgetPackagesRejectTraversalLinksAndKeepPreviousRegistry),
            ("Interactive widget state validates and persists", widgetItemsPersistAndValidateStateWithoutBecomingPhotos),
            ("New widgets avoid fixed items and each other", newWidgetsChooseSeparateSpaceAroundFixedItems)
        ]
        var failures = 0
        for (name, body) in cases {
            do { try await body(); print("PASS \(name)") }
            catch { failures += 1; print("FAIL \(name): \(error)") }
        }
        print("\(cases.count - failures)/\(cases.count) checks passed")
        if failures > 0 { exit(1) }
    }
}

@MainActor func strictToolArgumentValidation() throws {
    try CorkTools.validate(name: "cork_add_note", arguments: ["text": .string("A note"), "style": .string("flat")])
    try expectThrows { try CorkTools.validate(name: "cork_add_note", arguments: ["text": .bool(true)]) }
    try expectThrows { try CorkTools.validate(name: "cork_add_image", arguments: ["path": .string("/tmp/x.png"), "style": .string("sticky")]) }
    try expectThrows { try CorkTools.validate(name: "cork_get_board", arguments: ["extra": .bool(true)]) }
    try expectThrows { try CorkTools.validate(name: "cork_update_items", arguments: ["items": .array([])]) }
}
