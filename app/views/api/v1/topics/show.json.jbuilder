json.partial! 'api/v1/topics/topic', topic: [@topic, @pagy.count]

json.repositories do
  json.array! @repositories, partial: 'api/v1/repositories/repository', as: :repository
end

json.related_topics do
  json.array! @related_topics, partial: 'api/v1/topics/topic', as: :topic
end