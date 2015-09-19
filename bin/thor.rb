require "thor"
require "rest-client"
require "yaml"
require "json"

class Quiz < Thor

  BaseQURL = 'https://account.bilibili.com/answer/getBaseQ'
  GoPromotionURL = 'https://account.bilibili.com/answer/goPromotion'
  QstByTypeURL = 'https://account.bilibili.com/answer/getQstByType'
  ProTypeURL = 'https://account.bilibili.com/answer/getProType'

  ProjectRoot = File.expand_path('../..', __FILE__)
  QuizYamlFile = File.join(ProjectRoot, 'db/quiz.yml')
  QuizTypesYamlFile = File.join(ProjectRoot, 'db/quiz_types.yml')
  AuthCookieFile = File.join(ProjectRoot, 'db/auth_cookies.yml')

  class Retry < Exception; end
  class UnAuth < Exception; end
  class Unknown < Exception
    attr_reader :data

    def initialize data
      @data = data
      super
    end
  end

  desc "grab", "Grab quiz and store in yaml file"
  def grab
    loop do
      merge_quiz_yaml load_quiz
    end
  rescue Interrupt
  rescue UnAuth
    say_status :error, "Bilibili auth cookie expired, please update it in `db/auth_cookies.yml'", :red
  rescue Unknown => error
    response = error.data
    if response["message"] == -1
      reauth
      retry
    else
      say_status :error, "Unknown error #{response}", :red
    end
  ensure
    dump_quiz_yaml
  end

  desc "info", ""
  def info
    puts "Quiz: #{all_quiz.length}"
    grouped_quiz = all_quiz.group_by do |id, quiz|
      quiz["type"].class
    end
    grouped_quiz[Array] = grouped_quiz[Array].group_by do |id, quiz|
      quiz["type"].length
    end

    puts "  with specific type: #{grouped_quiz[Fixnum].length}"
    puts "  with 2 types: #{grouped_quiz[Array][2].length}"
    puts "  with 3 types: #{grouped_quiz[Array][3].length}"
  end

private

  def auth_cookie
    return @auth_cookie.sample if @auth_cookie

    say_status :info, "Loading cookie for authentication..."
    @auth_cookie = YAML.load_file(AuthCookieFile)
    @auth_cookie.sample
  end

  def quiz_type_ids
    if @quiz_type_ids
      @request_count += 1
      @weight_sum += @weight_length
      @weight_avg = @weight_sum / @request_count

      if @weight_avg >= @weight_length
        @last_quiz_type_ids = @quiz_type_ids.sample(3)
      end

      # say_status :debug, "request_count: #{@request_count}"
      # say_status :debug, "weight_sum: #{@weight_sum}"
      # say_status :debug, "weight_avg: #{@weight_avg}"
      # say_status :debug, "weight_length: #{@weight_length}"
      # say_status :debug, "quiz_type_ids: #{@last_quiz_type_ids}"

      return @last_quiz_type_ids
    end

    @request_count = 0
    @weight_sum = 0

    say_status :info, "Grabbing quiz types..."
    response = request ProTypeURL

    say_status :info, "Dumping quiz types to yaml file..."
    File.open(QuizTypesYamlFile, 'w') do |file|
      YAML.dump response["data"]["list"], file
    end

    @quiz_type_ids = response["data"]["list"].map do |type|
      type["fields"].map do |subtype|
        subtype["id"]
      end
    end.flatten

    @quiz_type_ids.sample(3)
  end

  def load_quiz
    say_status :info, "Grabbing new quiz form..."

    type_ids = quiz_type_ids
    response = request QstByTypeURL, type_ids: type_ids.join(",")

    new_quiz = format_quiz response["data"], type_ids

    new_quiz
  end

  def all_quiz
    return @all_quiz if @all_quiz

    say_status :info, "Loading quiz from yaml file..."
    @all_quiz = YAML.load_file(QuizYamlFile) || {}
    say_status :info, "Loaded #{@all_quiz.length} quiz from yaml file."
    @all_quiz
  end

  def merge_quiz_yaml new_quiz
    update_quiz_types_length = 0
    (new_quiz.keys & all_quiz.keys).each do |key|
      all_type = all_quiz[key]["type"]
      next if all_type.nil?

      new_quiz[key]["type"] = all_type and next if all_type.kind_of?(Integer)

      all_type.sort!
      new_type = new_quiz[key]["type"].sort
      next if all_type == new_type

      update_quiz_types_length += 1
      new_type = new_type & all_type
      new_type = new_type.first if new_type.length <= 1

      # say_status :debug, "type: #{all_type} => #{new_type}"

      new_quiz[key]["type"] = new_type
    end

    new_quiz_length = new_quiz.length

    say_status :info, "Got #{new_quiz_length} new quiz, update #{update_quiz_types_length} quiz types, #{all_quiz.length + new_quiz_length} in total."

    @weight_length = new_quiz_length + update_quiz_types_length
    all_quiz.merge! new_quiz
  end

  def dump_quiz_yaml
    return if @all_quiz.nil? || @all_quiz.empty?

    say_status :info, "Dumping #{all_quiz.length} quiz to yaml file..."
    File.open(QuizYamlFile, 'w') do |file|
      YAML.dump all_quiz, file
    end
  end

  def format_quiz quiz, type_ids

    quiz = quiz.reduce Hash.new do |hash, quiz|
      hash[quiz["qs_id"]] = quiz
      hash
    end

    quiz_ids = quiz.keys.map(&:to_i).sort
    format_quiz = quiz_ids.reduce Hash.new do |hash, id|
      raw_quiz = quiz[id.to_s]

      answers = (1..4).map do |index| {
          "answer" => raw_quiz["ans#{index}"],
          "hash" => raw_quiz["ans#{index}_hash"]
        }
      end.sort_by do |answer|
        answer["hash"]
      end

      hash[id] = {
        "question" => raw_quiz["question"],
        "answers" => answers,
        "type" => type_ids,
      }

      hash
    end

    format_quiz
  end

  def reauth
    say_status :info, "Grabbing base quiz..."
    response = request BaseQURL

    base_quiz = response["data"]["questionList"].reduce Hash.new do |hash, quiz|
      hash[quiz["qs_id"]] = quiz
      hash
    end

    result = {}
    result["qs_ids"] = base_quiz.keys.join(",")

    reauth_next_try = proc do |update_ids, ans_hash|
      update_ids.each do |id|
        result["ans_hash_#{id}"] = base_quiz[id][ans_hash]
      end

      response = request GoPromotionURL, result, false
      return if response["status"]
    end

    reauth_next_try.call base_quiz.keys, "ans1_hash"
    reauth_next_try.call response["message"], "ans2_hash"
    reauth_next_try.call response["message"], "ans3_hash"
    reauth_next_try.call response["message"], "ans4_hash"

    validate(response)
  rescue Unknown => error
    response = error.data
    say_status :error, "Unknown error #{response}", :red
    exit -1
  end

  def request url, data = nil, validation = true
    response = RestClient.post url, data, Cookie: auth_cookie
    response = JSON.parse(response.body)
    validate response if validation
    response
  end

  def validate response
    raise Unknown, response unless response["status"]
  end


end

Quiz.start(ARGV)
