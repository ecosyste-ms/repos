module Hosts
  # Hosts such as Bitbucket report language names in lowercase ("java"),
  # while GitHub reports Linguist names ("Java"). Map any case variant of a
  # known Linguist language to its canonical spelling so values group and
  # filter consistently. Unknown names are returned unchanged.
  module LanguageNormalizer
    CANONICAL_NAMES = YAML.load_file(Rails.root.join('config', 'linguist_languages.yml')).freeze
    BY_DOWNCASED_NAME = CANONICAL_NAMES.index_by(&:downcase).freeze

    def self.normalize(language)
      return language unless language.is_a?(String)

      name = language.strip
      BY_DOWNCASED_NAME.fetch(name.downcase, name.presence)
    end
  end
end
