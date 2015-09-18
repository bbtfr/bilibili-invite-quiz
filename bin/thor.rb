require "thor"
require "rest-client"
require "yaml"
require "json"

class Quiz < Thor

  BaseQUrl = 'https://account.bilibili.com/answer/getBaseQ'
  QstByTypeUrl = 'https://account.bilibili.com/answer/getQstByType'
  ProTypeUrl = 'https://account.bilibili.com/answer/getProType'

  ProjectRoot = File.expand_path('../..', __FILE__)
  QuizYamlFile = File.join(ProjectRoot, 'db/quiz.yml')
  QuizTypesYamlFile = File.join(ProjectRoot, 'db/quiz_types.yml')
  AuthCookieFile = File.join(ProjectRoot, 'db/auth_cookies.yml')

  desc "grab", "Grab invite quiz and store in yaml file"
  def grab
    while true
      merge_quiz_yaml load_quiz
    end
  end

private

  def auth_cookie
    return @auth_cookie.sample if @auth_cookie

    say_status :info, "Loading cookie for authentication..."
    @auth_cookie = YAML.load_file(AuthCookieFile)
    @auth_cookie.sample
  end

  def quiz_type_ids
    return @quiz_type_ids.sample(3).join(",") if @quiz_type_ids

    say_status :info, "Grabbing quiz types..."
    response = RestClient.post ProTypeUrl, nil, Cookie: auth_cookie
    response = JSON.parse(response.body)

    say_status :info, "Dumping quiz types to yaml file..."
    File.open(QuizTypesYamlFile, 'w') do |file|
      YAML.dump response, file
    end

    @quiz_type_ids = response["data"]["list"].map do |type|
      type["fields"].map do |subtype|
        subtype["id"]
      end
    end.flatten

    @quiz_type_ids.sample(3).join(",")
  end

  def load_quiz
    say_status :info, "Grabbing new invite quiz form..."

    response = RestClient.post QstByTypeUrl, { type_ids: "11,12,13,14,15,16,19" }, Cookie: auth_cookie
    response = JSON.parse(response.body)

    unless response["status"]
      say_status :error, "Bilibili server responded: #{response}"
      exit -1
    end

    new_quiz = response["data"].reduce Hash.new do |hash, quiz|
      hash[quiz["qs_id"]] = quiz
      hash
    end

    say_status :info, "Got #{new_quiz.length} invite quiz."
    new_quiz
  end

  def quiz
    return @quiz if @quiz

    say_status :info, "Loading invite quiz from yaml file..."
    @quiz = YAML.load_file(QuizYamlFile) || {}
    say_status :info, "Loaded #{@quiz.length} invite quiz from yaml file."
    @quiz
  end

  def merge_quiz_yaml new_quiz
    new_quiz_length = (new_quiz.keys - quiz.keys).length
    say_status :info, "Got #{new_quiz_length} new invite quiz, #{quiz.length} in total."
    return if new_quiz_length.zero?

    quiz.merge! new_quiz

    say_status :info, "Dumping invite quiz to yaml file..."
    File.open(QuizYamlFile, 'w') do |file|
      YAML.dump quiz, file
    end
  end



end

Quiz.start(ARGV)
