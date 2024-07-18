require 'pagy/extras/headers'
require 'pagy/extras/items'
require 'pagy/extras/countless'
require 'pagy/extras/bootstrap'
require 'pagy/extras/array'
require 'pagy/extras/overflow'
require 'pagy/extras/i18n'

Pagy::DEFAULT[:items] = 100
Pagy::DEFAULT[:items_param] = :per_page
Pagy::DEFAULT[:max_items] = 1000
Pagy::DEFAULT[:overflow] = :empty_page