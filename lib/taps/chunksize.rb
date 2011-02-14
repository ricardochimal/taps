require 'taps/errors'

class Taps::Chunksize
  attr_accessor :idle_secs, :time_in_db, :start_time, :end_time, :retries
  attr_reader :chunksize

  def initialize(chunksize)
    @chunksize = chunksize
    @idle_secs = 0.0
    @retries = 0
  end

  def to_i
    chunksize
  end

  def reset_chunksize
    @chunksize = (retries <= 1) ? 10 : 1
  end

  def diff
    end_time - start_time - time_in_db - idle_secs
  end

  def time_in_db=(t)
    @time_in_db = t
    @time_in_db = @time_in_db.to_f rescue 0.0
  end

  def time_delta
    t1 = Time.now
    yield if block_given?
    t2 = Time.now
    t2 - t1
  end

  def calc_new_chunksize
    new_chunksize = if retries > 0
      chunksize
    elsif diff > 3.0
      (chunksize / 3).ceil
    elsif diff > 1.1
      chunksize - 100
    elsif diff < 0.8
      chunksize * 2
    else
      chunksize + 100
    end
    new_chunksize = 1 if new_chunksize < 1
    new_chunksize
  end
end
