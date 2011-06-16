module RackDAV

  # Quick & Dirty
  class LockableFileResource < FileResource
    @@locks = {}

    def lock(token, timeout, scope = nil, type = nil, owner = nil)
      if scope && type && owner
        # Create lock
        @@locks[token] = {
          :timeout => timeout,
          :scope   => scope,
          :type    => type,
          :owner   => owner
        }
        return true
      else
        # Refresh lock
        lock = @@locks[token]
        return false unless lock
        return [ lock[:timeout], lock[:scope], lock[:type], lock[:owner] ]
      end
    end

    def unlock(token)
      !!@@locks.delete(token)
    end
  end

end
