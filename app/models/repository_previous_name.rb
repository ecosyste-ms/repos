class RepositoryPreviousName < ApplicationRecord
  belongs_to :host
  belongs_to :repository
end
