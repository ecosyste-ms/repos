# Monkey patch to fix Semantic::Version handling of leading zeros in identifiers
# The original gem uses Integer() which fails on "0009" - we use to_i instead
module Semantic
  class Version
    def identifiers(pre)
      array = pre.split(/[\.\-]/)
      array.map! { |e| /\A\d+\z/.match?(e) ? e.to_i : e }
    end
  end
end