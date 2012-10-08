require 'active_support/concern'
require 'active_support/core_ext/date/conversions'


module Hiccup
  module Inferrable
    extend ActiveSupport::Concern
    
    module ClassMethods
      
      
      
      def infer(dates, options={})
        @verbose = options.fetch(:verbose, false)
        dates = extract_array_of_dates!(dates)
        guesses = generate_guesses(dates)
        guess, score = pick_best_guess(guesses, dates)
        guess
      end
      
      
      
      def generate_guesses(dates)
        start_date = dates.min
        end_date = dates.max
        guesses = []
        
        
        (1...5).each do |skip|
          guesses << self.new.tap do |schedule|
            schedule.kind = :annually
            schedule.start_date = start_date
            schedule.end_date = end_date
            schedule.skip = skip
          end
        end
        
        (1...5).each do |skip|
          guesses << self.new.tap do |schedule|
            schedule.kind = :monthly
            schedule.start_date = start_date
            schedule.end_date = end_date
            schedule.skip = skip
            schedule.monthly_pattern = [start_date.day]
          end
          
          guesses << self.new.tap do |schedule|
            schedule.kind = :monthly
            schedule.start_date = start_date
            schedule.end_date = end_date
            schedule.skip = skip
            schedule.monthly_pattern = dates.map { |date|
              [date.get_nth_wday_of_month, Date::DAYNAMES[date.wday]]
            }.uniq
          end
        end
        
        (1...5).each do |skip|
          guesses << self.new.tap do |schedule|
            schedule.kind = :weekly
            schedule.start_date = start_date
            schedule.end_date = end_date
            schedule.skip = skip
            # schedule.weekly_pattern = histogram_of_wdays.keys.map { |wday| Date::DAYNAMES[wday] }
            schedule.weekly_pattern = dates.map(&:wday).uniq.map { |wday| Date::DAYNAMES[wday] }
          end
        end
        
        guesses
      end
      
      
      
      def pick_best_guess(guesses, dates)
        scored_guesses = guesses \
          .map { |guess| [guess, score_guess(guess, dates)] } \
          .sort_by { |(guess, score)| -score.to_f }
        
        if @verbose
          puts "\nGUESSES FOR #{dates}:"
          scored_guesses.each do |(guess, score)|
            puts "  (%.3f p/%.3f b/%.3f c/%.3f) #{guess.humanize}" % [
              score.to_f,
              score.prediction_rate,
              score.brick_penalty,
              score.complexity_penalty]
          end
          puts ""
        end
        
        scored_guesses.reject { |(guess, score)| score.to_f < 0.500 }.first
      end
      
      def score_guess(guess, input_dates)
        predicted_dates = guess.occurrences_between(guess.start_date, guess.end_date)
        
        # prediction_rate is the percent of input dates predicted
        predictions = (predicted_dates & input_dates).length
        prediction_rate = Float(predictions) / Float(input_dates.length)
        
        # bricks are dates predicted by this guess but not in the input
        bricks = (predicted_dates - input_dates).length
        
        # brick_rate is the percent of bricks to predictions
        # A brick_rate >= 1 means that this guess bricks more than it predicts
        brick_rate = Float(bricks) / Float(input_dates.length)
        
        # complexity measures how many rules are necesary
        # to describe the pattern
        complexity = complexity_of(guess)
        
        Score.new(prediction_rate, brick_rate, complexity)
      end
      
      def complexity_of(schedule)
        return schedule.weekly_pattern.length if schedule.weekly?
        return schedule.monthly_pattern.length if schedule.monthly?
        1
      end
      
      
      
      def extract_array_of_dates!(dates)
        raise_invalid_dates_error! unless dates.respond_to?(:each)
        dates.map { |date| assert_date!(date) }.sort
      end
      
      def assert_date!(date)
        return date if date.is_a?(Date)
        date.to_date rescue raise_invalid_dates_error!
      end
      
      def raise_invalid_dates_error!
        raise ArgumentError.new("Inferrable.infer expects to receive a collection of dates")
      end
      
      
      
      class Score < Struct.new(:prediction_rate, :brick_rate, :complexity)
        
        # as brick rate rises, our confidence in this guess drops
        def brick_penalty
          brick_penalty = brick_rate * 0.33
          brick_penalty = 1 if brick_penalty > 1
          brick_penalty
        end
        
        # as the complexity rises, our confidence in this guess drops
        # this hash table is a stand-in for a proper formala
        def complexity_penalty
          {1 => 0, 2 => 0.10, 3 => 0.25, 4 => 0.45, 5 => 0.70}.fetch(complexity, 0.90)
        end
        
        # our confidence is weakened by bricks and complexity
        def confidence
          confidence = 1.0
          confidence *= (1 - brick_penalty)
          confidence *= (1 - complexity_penalty)
          confidence
        end
        
        # a number between 0 and 1
        def to_f
          prediction_rate * confidence
        end
        
      end
      
      
    end
  end
end
