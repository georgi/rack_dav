class String

  if RUBY_VERSION >= "1.9"
    def force_valid_encoding
      find_encoding(Encoding.list.to_enum)
    end
  else
    def force_valid_encoding
      self
    end
  end

  private

  def find_encoding(encodings)
    if valid_encoding?
      self
    else
      force_next_encoding(encodings)
    end
  end

  def force_next_encoding(encodings)
    force_encoding(encodings.next)
    find_encoding(encodings)
  end

end
