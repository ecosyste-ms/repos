json.name topic[0]
json.repositorys_count topic[1]
if params[:host_id]
  json.host api_v1_host_topic_url(host_id: params[:host_id], id: topic[0])
else
  json.topic_url api_v1_topic_url(id: topic[0])
end
