json.name @topic
json.repositories_count @pagy.count
json.topic_url api_v1_topic_url(id: @topic)

json.repositories do
  json.array! @repositories, partial: 'api/v1/repositories/repository', as: :repository
end

json.related_topics @related_topics