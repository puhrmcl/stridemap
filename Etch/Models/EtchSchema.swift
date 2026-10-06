import Foundation
import SwiftData

/// The store's schema, versioned, and the plan for moving between versions.
///
/// This exists because of what happens without it. `ModelContainer(for: Run.self, …)` infers an
/// unversioned schema from whatever the model types look like today. That is fine while the only
/// library in existence is a developer's, because a failure to open is a reinstall away. The day
/// v1.0 is on the App Store it stops being fine: the next release that adds a property changes
/// the inferred schema, SwiftData has no description of what shipped and no instructions for
/// getting from it to the new shape, and every existing user's app fails to open its store on
/// launch — with their whole history inside it.
///
/// Declaring V1 now is what makes that recoverable later. It pins what shipped, so a future
/// version can be written as a migration *from a known starting point* rather than from an
/// archaeology exercise against a schema nobody recorded.
///
/// ## Adding a version
///
/// 1. Copy the model types as they exist **today** into a frozen `EtchSchemaV1` namespace — a
///    version's models must stop tracking the live source, or the description of what shipped
///    changes under you on the next edit.
/// 2. Add `EtchSchemaV2` with the new shape and append it to `schemas`.
/// 3. Add a `MigrationStage` between them. Lightweight is enough for added optional properties
///    and renames with `@Attribute(originalName:)`; anything that has to compute a value, split a
///    model or enforce a new uniqueness constraint needs a custom stage.
///
/// Until step 1 happens, V1 references the live types, which is correct while V1 *is* the live
/// shape and wrong the moment it is not.
enum EtchSchemaV1: VersionedSchema {

    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] { [Run.self, SavedPoster.self] }
}

/// The ordered history of schemas and how to get between them.
///
/// One version so far, so there is nothing to migrate yet and `stages` is empty. The plan is
/// still worth installing now: a container opened *with* a migration plan records which version
/// it is on, and a container opened without one does not.
enum EtchMigrationPlan: SchemaMigrationPlan {

    static var schemas: [any VersionedSchema.Type] { [EtchSchemaV1.self] }

    static var stages: [MigrationStage] { [] }
}

/// How the app opened its store, and what to do about it.
enum StoreOpening {

    /// The store opened normally.
    case ready(ModelContainer)

    /// The store could not be opened. The container here is in memory, so the app can render an
    /// explanation instead of crashing — and, importantly, the file on disk is left exactly as it
    /// was. A library that cannot be read today may be readable by the next release; deleting it
    /// to get a clean launch would turn a bad morning into permanent data loss.
    case failed(ModelContainer, Error)

    var container: ModelContainer {
        switch self {
        case .ready(let container), .failed(let container, _): return container
        }
    }

    var failure: Error? {
        switch self {
        case .ready: return nil
        case .failed(_, let error): return error
        }
    }

    /// Opens the on-disk store, falling back to an in-memory one that carries the error.
    ///
    /// The fallback is deliberately *not* a fresh on-disk store: writing a new empty file where
    /// the old one stood is indistinguishable, from the user's side, from the app having thrown
    /// their history away — because it has.
    static func open() -> StoreOpening {
        let schema = Schema(versionedSchema: EtchSchemaV1.self)
        do {
            let container = try ModelContainer(for: schema, migrationPlan: EtchMigrationPlan.self)
            return .ready(container)
        } catch {
            do {
                let memory = try ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                )
                return .failed(memory, error)
            } catch {
                // An in-memory store of the same schema failing means the schema itself cannot be
                // realised, which no amount of runtime handling recovers from.
                fatalError("Could not create even an in-memory container: \(error)")
            }
        }
    }
}
