json.name topic.name
json.repositories_count topic.repositories_count
if params[:host_id]
  json.host api_v1_host_topic_url(host_id: params[:host_id], id: topic.name)
else
  json.topic_url api_v1_topic_url(id: topic.name)
end
