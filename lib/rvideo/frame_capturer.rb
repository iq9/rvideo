module RVideo
  # FrameCapturer uses ffmpeg to capture frames from a movie in JPEG format.
  #
  # You can capture one or many frames in a variety of ways:
  #
  #   - one frame at a given offset
  #   - multiple frames every n seconds from a given offset
  #
  # TODO
  #
  #   - n frames total, evenly distributed across the duration of the movie
  #
  # For the offset options, three types of values are accepted:
  #   - percentage e.g. '37%'
  #   - seconds    e.g. '37s' or simply '37'
  #   - frame      e.g. '37f'
  #
  # If a time is outside of the duration of the file, it will choose a frame at the
  # 99% mark.
  #
  # Example:
  #
  #   RVideo::FrameCapturer.capture! :input => 'path/to/input.mp4', :offset => '10%'
  #   # => ['/path/to/screenshot/input-10p.jpg']
  #
  # In the case where you specify an :interval, e.g. :interval => 5 for a frame every
  # 5 seconds, you will generally get a few more images that you might expect.
  # Typically there will be at least two extra, one for the very start and one for
  # the very end of the video. Then, depending on how close to a simple integer of
  # seconds the duration of the video is, you may get one or two more.
  #
  #   # Assuming input.mp4 is 19.6 seconds long..
  #   RVideo::FrameCapturer.capture! :input => 'path/to/input.mp4', :interval => 5
  #   # => ['/path/to/input-1.jpg','/path/to/input-2.jpg','/path/to/input-3.jpg',
  #         '/path/to/input-4.jpg','/path/to/input-5.jpg','/path/to/input-6.jpg']
  #
  # For more precision, you can try multiple capture commands, each getting
  # a single frame but with increasing offsets.
  class FrameCapturer
    attr_reader :input, :output, :offset, :rate, :limit, :inspector, :command

    def self.capture!(options)
      new(options).capture!
    end

    def initialize(options)
      @ffmpeg_binary = options[:ffmpeg_binary] || "ffmpeg"

      @input = options[:input] || raise(ArgumentError, "need :input => /path/to/movie")

      @inspector = Inspector.new :file => @input

      @offset, @rate, @limit, @output = parse_options options
      @command = create_command(@input, @output, @offset)
    end

    def capture!
      RVideo.logger.info("\nCreating Screenshot: #{@command}\n")
      frame_result = do_execute("#{@command} 2>&1")
      RVideo.logger.info("\nScreenshot results: #{frame_result}")

      Dir[File.expand_path(@output).sub("%d", "*")].entries
    end

    def do_execute(command)
      `#{command}`
    end

    VALID_TIMECODE_FORMAT = /\A([0-9.,]*)(s|f|%)?\Z/

    # TODO This method should not be public, but I'm too lazy to update the specs right now..
    def calculate_time(timecode)
      m = VALID_TIMECODE_FORMAT.match(timecode.to_s)
      if m.nil? or m[1].nil? or m[1].empty?
        raise TranscoderError::ParameterError,
          "Invalid timecode for frame capture: #{timecode}. " <<
        "Must be a number, optionally followed by s, f, or %."
      end

      case m[2]
      when "s", nil
        t = m[1].to_f
      when "f"
        t = m[1].to_f / @inspector.fps.to_f
      when "%"
        # milliseconds / 1000 * percent / 100
        t = (@inspector.duration.to_i / 1000.0) * (m[1].to_f / 100.0)
      else
        raise TranscoderError::ParameterError,
          "Invalid timecode for frame capture: #{timecode}. " <<
        "Must be a number, optionally followed by s, f, or p."
      end

      if (t * 1000) > @inspector.duration
        calculate_time("99%")
      else
        t
      end
    end

    private

    def create_command(input, output, offset)
      options = {:input_file => input, :output_file => output}
      # Putting `offset` prior to `-i` arg makes screengrabs faster, but at the expense of reliability.
      # It will generate a all-gray frame with some older MPEG 1 and 2's.
      ffmpeg = RVideo::Tools::Ffmpeg.new("#{@ffmpeg_binary} -i $input_file$ -ss #{offset} -vframes 1 -vcodec mjpeg -y -f image2 $resolution$ $output_file$", options)
      ffmpeg.command
    end

    def parse_options(options)
      offset = options[:offset] ? calculate_time(options[:offset]) : 0
      rate   = options[:interval] ? (1 / options[:interval].to_f) : 1

      limit  = nil
      # if options[:limit]
      #   options[:limit]
      # elsif not options[:interval]
      #   1
      # end

      output = if options[:output]
      options[:output]
    else
      path = File.dirname File.expand_path(options[:input])

      name = File.basename(options[:input], ".*")
      if options[:interval]
        name << "-%d"
      else
        name << "-#{offset}"
      end
      name << ".jpg"

      File.join path, name
    end

    [offset, rate, limit, output]
  end
end
end
