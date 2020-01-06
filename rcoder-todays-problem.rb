require 'faraday'
require 'faraday_middleware'
require 'json'

def run(args)
    conn = Faraday.new do |faraday|
        faraday.request :json
        faraday.response :json, :parser_options => { :symbolize_names => true }, :content_type => /\bjson$/
        faraday.adapter Faraday.default_adapter
    end

    response = conn.get("https://kenkoooo.com/atcoder/resources/merged-problems.json")
    raise "Failed to aquire problem list" if !response.success?
    problems = response.body
        .select{|problem| 
            ["abc", "agc"].include?(problem[:contest_id][0..2]) && problem[:point] && problem[:point] <= 400
        }
        .each{|problem| problem[:ac_count] = 0}
    
    response = conn.get("https://sheetdb.io/api/v1/iywg2l8ie54bt")
    raise "Failed to aquire IDs" if !response.success?
    users = response.body
    users_acs = users.map { |user|
        user_id = user[:user_id]
        response = conn.get("https://kenkoooo.com/atcoder/atcoder-api/results?user=#{user_id}")
        if response.success?
            response.body
                .select{|sub| sub[:result] == "AC"}
                .uniq{|sub| [sub[:problem_id], sub[:user_id]]}
        else
            nil
        end
    }.compact.flatten
    
    users_acs.each do |ac|
        problem_idx = problems.find_index{|problem| problem[:id] == ac[:problem_id]}
        problems[problem_idx][:ac_count] += 1 if problem_idx
    end

    ac_count, least_solved_problems = problems.group_by{|problem| problem[:ac_count]}.sort[0]

    raise "All candidate problems are solved by all members!" if ac_count == users.length
    
    todays_problem = least_solved_problems.sample

    puts "todays_problem is "
    pp todays_problem
    
    response = conn.post do |req|
        req.url  ENV["RCODER_SLACK_WEBHOOK"]
        req.body = {
            text: "<https://atcoder.jp/contests/#{todays_problem[:contest_id]}/tasks/#{todays_problem[:id]}|#{todays_problem[:title]}>",
            blocks: [
                {
                    type: :section,
                    text: {
                        type: :plain_text,
                        text: "Let's solve this today!",
                        emoji: true
                    }
                },
                {
                    type: :divider
                },
                {
                    type: :section,
                    text: {
                        type: :mrkdwn,
                        text: "*<https://atcoder.jp/contests/#{todays_problem[:contest_id]}/tasks/#{todays_problem[:id]}|#{todays_problem[:title]}>* (Points: #{todays_problem[:point].to_i})"
                    },
                    accessory: {
                        type: :button,
                        text: {
                            type: :plain_text,
                            text: "Open",
                            emoji: true
                        },
                        url: "https://atcoder.jp/contests/#{todays_problem[:contest_id]}/tasks/#{todays_problem[:id]}"
                    }
                },
                {
                    type: :divider
                }
            ]
        }
    end
    raise "Failed to send message to Slack" if !response.success?

    return todays_problem
end
