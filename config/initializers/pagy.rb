require 'pagy/extras/headers'
require 'pagy/extras/limit'
require 'pagy/extras/countless'
require 'pagy/extras/bootstrap'
require 'pagy/extras/array'
require 'pagy/extras/overflow'
require 'pagy/extras/i18n'

Pagy::DEFAULT[:limit] = 100
Pagy::DEFAULT[:limit_param] = :per_page
Pagy::DEFAULT[:limit_max] = 1000
Pagy::DEFAULT[:max_pages] = 1000
Pagy::DEFAULT[:overflow] = :empty_page