require 'cgi'
require 'io/console'
require 'json'
require 'ascii_charts'
require 'active_support/core_ext/numeric/time'
require 'terminal-table'
require 'byebug'

# utility methods
def sum(array)
  array.inject(0) { |sum, x| sum + x }
end

def get_points(issues)
  sum(issues.collect {|i| i[:points]}).to_i
end

# input methods
def get_input(prompt="Input: ")
  print prompt
  STDIN.gets.chomp
end
def get_password(prompt="Password: ")
  print prompt
  STDIN.noecho(&:gets).chomp
end

# Jira queries

def load_tasks
  query = "sprint = '#{@sprint}'"
  response = `curl -u #{@user}:#{@password}  "https://#{@subdomain}.atlassian.net/rest/api/2/search?jql=#{CGI.escape(query)}&expand=changelog,subtasks&maxResults=3000"`
  full_issues = JSON.parse(response)
  if full_issues["total"] > full_issues["maxResults"]
    puts "WARNING: not all issues where downloaded. Only #{full_issues["maxResults"]} out of #{full_issues["total"]}"
  end
  full_issues
end

def load_subtask(key)
  puts "loading: #{key}"
  response = `curl -u #{@user}:#{@password}  "https://#{@subdomain}.atlassian.net/rest/api/2/issue/#{key}?expand=changelog"`
  issue = JSON.parse(response)
  get_fields(issue)
end

# Jira result parsing

def status_history(issue)
  statuses = []
  issue["changelog"]["histories"].each do |history|
    history["items"].each do |item|
      statuses << {date: history["created"], status: item["toString"]} if item["field"] == "status"
    end
  end
  statuses
end

def get_fields(issue)
  fields = {
    key: issue["key"],
    title: issue["fields"]["summary"],
    status: issue["fields"]["status"]["name"],
    statuses: status_history(issue),
    assignee: issue["fields"]["assignee"] ? issue["fields"]["assignee"]["name"] : nil,
    team:   issue["fields"]["customfield_10501"] ? issue["fields"]["customfield_10501"].collect{|c| c["value"]} : [],
    component: issue["fields"]["components"] ? issue["fields"]["components"].collect{|c| c["name"]} : [],
    points: issue["fields"]["customfield_10004"],
    issue_type: issue["fields"]["subtasks"] && issue["fields"]["subtasks"].any? ? "subtask" : "story",
    subtasks: issue["fields"]["subtasks"] ? issue["fields"]["subtasks"].collect do |subtask|
      load_subtask(subtask["key"])
    end : []
  }
  fields[:team_and_component] =  (fields[:component]+fields[:team]).compact.uniq.join(", ")
  fields
end

# main
#====================

# params

# Parameters - FIXME: clean this up, i.e use OptionParser
@subdomain = get_input("Jira subdomain: ")
@sprint = get_input("Jira sprint name: ")
@user = get_input("Jira username: ")
@password = get_password("Jira password: ")

# get sprint start and end dates - figure out how to get these from Jira
@start_date = Date.parse("2016-03-07").at_beginning_of_day
@end_date   = Date.parse("2016-03-17").at_beginning_of_day

# query all issues
full_issues = load_tasks

# # File.open('issues.json', 'w') {|f| f.write(full_issues.issues.to_json) }
# full_issues = JSON.parse(IO.read("issues.json"))

issues = full_issues["issues"].collect {|issue| get_fields(issue) }.compact

# flatten - From a point perspective we select only stories with no subtask or all subtasks
flattened = []
issues.each do |issue|
  flattened << (issue[:issue_type] == "story" ? issue : issue[:subtasks])
end
issues = flattened.flatten.uniq
puts "Number of stories/subtask #{issues.length}."

# validation - show any relevant story without points

nopoints = []
issues.each do |issue|
  nopoints << "\t#{issue[:key]}: #{issue[:title]}" if issue[:points].nil?
end
if nopoints.any?
  puts "ERROR: add points to the following stories/subtasks: #{nopoints.length}"
  puts nopoints.join("\n")
  issues = issues.delete_if {|i| i[:points].nil?}
  puts "Number of stories/subtask #{issues.length}"
end

# validation - team assignment
teams = issues.collect {|i| i[:team]}.flatten.uniq.sort
all_teams = []
more_than_one_team = []  # Issues with more than one team must have subtasks and each subtask must be assigned to one team only.
no_team = []
teams.each do |team|
  team_issues = issues.select do |i|
    more_than_one_team << "\t#{i[:key]}: #{i[:title]}"  if i[:team].length > 1
    no_team << "\t#{i[:key]}: #{i[:title]}"  if i[:team].length == 0
    i[:team].first == team
  end
  team_issues = team_issues.uniq
  all_teams << [team, team_issues]
  # team_points << [team, get_points(team_issues)]
end

more_than_one_team = more_than_one_team.uniq.sort
no_team = no_team.uniq.sort
if more_than_one_team.any?
  puts "ERROR: Issues with more than one team must have subtasks and each subtask must be assigned to one team only: #{more_than_one_team.length}"
  puts more_than_one_team.join("\n")
end
if no_team.any?
  puts "ERROR: add team to the following stories/subtasks: #{no_team.length}"
  puts no_team.join("\n")
end

# table = Terminal::Table.new headings: ['Team', 'Points'], rows: team_points
# table.add_separator
# table.add_row ['Total', get_points(issues)]
# puts table
# puts

# summary teams and statuses
# statuses = issues.collect {|i| i[:status]}.compact.uniq
statuses = ["Open", "In Progress", "Awaiting Merge", "Awaiting Product Acceptance", "Awaiting QA Validation", "Resolved"]
statuses_label = ["Open", "Started", "Merge", "Product", "QA", "Resolved"]
team_points = []
# header
header_row = ["Team"]
statuses.each_with_index do |status, index|
  header_row << statuses_label[index]
end
header_row << "Total"
# teams
all_teams.each do |team_info|
  team, team_issues = team_info
  row = [team]
  statuses.each_with_index do |status, index|
    team_issues_with_status = team_issues.select {|i| i[:status]==status}
    row << get_points(team_issues_with_status)
  end
  row << get_points(team_issues)
  team_points << row
end
# total by status
footer_row = ["Total"]
statuses.each_with_index do |status, index|
  issues_with_status = issues.select {|i| i[:status]==status}
  footer_row << get_points(issues_with_status)
end
footer_row << get_points(issues)

table = Terminal::Table.new headings: header_row, rows: team_points
table.add_separator
table.add_row footer_row
puts table
puts

# summary by assignee
assignees = issues.collect {|i| i[:assignee]}.compact.uniq.sort
assignees_data = []
assignees.each_with_index do |assignee, index|
  assignee_issues = issues.select {|i| i[:assignee]==assignee}
  assignees_data << [assignee, get_points(assignee_issues)]
end

table = Terminal::Table.new headings: ['Assignee', 'Points'], rows: assignees_data
puts table
puts


def resolved?(issue, date)
  issue[:statuses].each do |status|
    return true if (status[:status] == "Resolved" || status[:status] == "Closed") && date >= Date.parse(status[:date]).at_beginning_of_day
  end
  return false
end

# 12 days - For each day figure how many points
def draw_chart(title, issues)
  total_points = get_points(issues)
  points_per_day = []
  11.times do |n|
    date = @start_date + n.day
    resolved_point = sum(issues.collect {|issue| resolved?(issue, date) ? issue[:points] : 0 }).to_i
    remaining_points = total_points - resolved_point
    remaining_points = 0 if date > Date.today
    points_per_day << [n+1, remaining_points]
  end
  puts AsciiCharts::Cartesian.new(points_per_day, :hide_zero => true, title: "#{title}  points:#{total_points}").draw
end


draw_chart "Sprint Burndown", issues
teams.each do |team|
  team_issues = issues.select {|i| i[:team].first == team} # Picking first team is not fair
  draw_chart "#{team} Burndown", team_issues
end

puts "Non resolved issues by team"

all_teams.each do |team_info|
  team, team_issues = team_info
  team_issues = team_issues.select {|i| i[:status]!="Resolved"}
  puts "Team: #{team} - number of issues:#{team_issues.length}  (#{get_points(team_issues)} points)"
  next if team_issues.length == 0
  (statuses - ["Resolved"]).each_with_index do |status, index|
    team_issues_with_status = team_issues.select {|i| i[:status]==status}
    next if team_issues_with_status.length == 0
    puts "\t#{status} (#{get_points(team_issues_with_status)} points)"
    team_issues_with_status.each do |team_issue|
      puts "\t\t#{team_issue[:key]}: #{team_issue[:title]}  (#{team_issue[:points]} points)"
    end
  end
end

puts "Done"
