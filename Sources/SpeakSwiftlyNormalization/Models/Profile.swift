public extension SpeakSwiftlyNormalization {
    struct Profile: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let name: String
        public let replacements: [Replacement]

        public init(
            id: String = "default",
            name: String = "Default",
            replacements: [Replacement] = [],
        ) {
            self.id = id
            self.name = name
            self.replacements = replacements
        }

        // MARK: Sorting

        private static func sortReplacements(
            lhs: Replacement,
            rhs: Replacement,
        ) -> Bool {
            if lhs.priority == rhs.priority {
                return lhs.id < rhs.id
            }

            return lhs.priority > rhs.priority
        }

        // MARK: Replacement Access

        public func replacements(
            for phase: Replacement.Phase,
            in format: TextFormat,
        ) -> [Replacement] {
            replacements
                .filter { $0.phase == phase && $0.applies(to: format) }
                .sorted(by: Self.sortReplacements)
        }

        public func replacements(
            for phase: Replacement.Phase,
            in format: SourceFormat,
        ) -> [Replacement] {
            replacements
                .filter { $0.phase == phase && $0.applies(to: format) }
                .sorted(by: Self.sortReplacements)
        }

        public func replacement(id: String) -> Replacement? {
            replacements.first { $0.id == id }
        }

        // MARK: Profile Composition

        public func merged(with custom: Self) -> Self {
            Self(
                id: custom.id,
                name: custom.name,
                replacements: replacements + custom.replacements,
            )
        }

        public func named(_ name: String) -> Self {
            Self(id: id, name: name, replacements: replacements)
        }

        // MARK: Replacement Mutation

        public func adding(_ replacement: Replacement) -> Self {
            Self(id: id, name: name, replacements: replacements + [replacement])
        }

        public func replacing(_ replacement: Replacement) throws -> Self {
            guard replacements.contains(where: { $0.id == replacement.id }) else {
                throw SpeakSwiftlyNormalization.ProfileError.replacementNotFound(
                    replacement.id,
                    profileID: id,
                )
            }

            return Self(
                id: id,
                name: name,
                replacements: replacements.map { existing in
                    existing.id == replacement.id ? replacement : existing
                },
            )
        }

        public func removingReplacement(id replacementID: String) throws -> Self {
            guard replacements.contains(where: { $0.id == replacementID }) else {
                throw SpeakSwiftlyNormalization.ProfileError.replacementNotFound(
                    replacementID,
                    profileID: id,
                )
            }

            return Self(
                id: id,
                name: name,
                replacements: replacements.filter { $0.id != replacementID },
            )
        }
    }
}
