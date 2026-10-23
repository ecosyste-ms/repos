module CachedHost
  def host
    association = association(:host)
    if !association.loaded? && host_id && (cached = Host.cached_find(host_id))
      association.target = cached
    end
    super
  end
end
