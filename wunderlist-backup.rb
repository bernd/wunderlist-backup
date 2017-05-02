#!/usr/bin/env ruby

# Copyright 2015 Bernd Ahlers
#
# The Netty Project licenses this file to you under the Apache License,
# version 2.0 (the "License"); you may not use this file except in compliance
# with the License. You may obtain a copy of the License at:
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

require 'net/http'
require 'json'
require 'time'


class WunderAuth
  Error = Class.new(Exception)

  def initialize(env)
    @env = env.to_hash
  end

  def access_token
    @env['WUNDERLIST_ACCESS_TOKEN']
  end

  def client_id
    @env['WUNDERLIST_CLIENT_ID']
  end

  def validate!
    unless access_token || client_id
      raise Error, "Missing environment variables: WUNDERLIST_ACCESS_TOKEN, WUNDERLIST_CLIENT_ID"
    end
    self
  end
end

class WunderHTTP
  def initialize(base_url, auth)
    @uri = URI.parse(base_url)
    @auth = auth
    @user = nil
    @http = Net::HTTP.new(@uri.host, @uri.port)
    @http.use_ssl = @uri.scheme == 'https'
    @cache = {}
  end

  def user_id
    @user ||= get('user')[:id]
  end

  %w(lists folders memberships).each do |name|
    define_method(name.to_sym) { get(name) }
  end

  %w(tasks reminders subtasks notes task_positions
     subtask_positions task_comments webhooks).each do |name|
    define_method(name.to_sym) {|id| get("#{name}?list_id=#{id}") }
  end

  def completed_tasks(id)
    get("tasks?list_id=#{id}&completed=true")
  end

  private

  def get(path, options = {})
    if @cache.has_key?(path)
      return @cache.fetch(path)
    end

    req = Net::HTTP::Get.new(@uri.merge(path))

    req['X-Access-Token'] = @auth.access_token
    req['X-Client-ID'] = @auth.client_id
    req['Accept'] = 'application/json; charset=utf-8'

    res = @http.start { @http.request(req) }

    case res
    when Net::HTTPSuccess
      @cache[path] = JSON.parse(res.body, symbolize_names: true)
    else
      puts "ERROR: #{res.code} - #{res.message}: #{res}"
      nil
    end
  end
end

class WunderBackup
  def initialize(user_id)
    @time = Time.now
    @user_id = user_id
    @data = {}
  end

  %w(lists tasks reminders subtasks notes task_positions subtask_positions
     folders memberships task_comments webhooks).each do |name|
    define_method(name.to_sym) do
      @data.fetch(name.to_sym, [])
    end

    define_method("add_#{name}") do |values|
      @data[name.to_sym] ||= []
      @data[name.to_sym].concat(Array(values))
    end
  end

  def to_hash
    {
      user: @user_id,
      exported: @time.iso8601,
      data: {
        lists: lists,
        tasks: tasks,
        reminders: reminders,
        subtasks: subtasks,
        notes: notes,
        task_positions: task_positions,
        subtask_positions: subtask_positions,
        folders: folders,
        memberships: memberships,
        task_comments: task_comments,
        webhooks: webhooks
      }
    }
  end
end


auth = WunderAuth.new(ENV).validate!
wunder = WunderHTTP.new('https://a.wunderlist.com/api/v1/', auth)
backup = WunderBackup.new(wunder.user_id)

STDERR.puts "Initialized."
backup.add_lists(wunder.lists)
backup.add_folders(wunder.folders)

STDERR.puts "Processing #{wunder.lists.length} lists..."

wunder.lists.each_with_index do |list, index|
  STDERR.puts "   ... (#{index + 1}/#{wunder.lists.length}) #{list[:title]} ..."
  STDERR.puts "      ... tasks"
  backup.add_tasks(wunder.tasks(list[:id]))
  STDERR.puts "      ... completed tasks"
  backup.add_tasks(wunder.completed_tasks(list[:id]))
  STDERR.puts "      ... reminders"
  backup.add_reminders(wunder.reminders(list[:id]))
  STDERR.puts "      ... subtasks"
  backup.add_subtasks(wunder.subtasks(list[:id]))
  STDERR.puts "      ... notes"
  backup.add_notes(wunder.notes(list[:id]))
  STDERR.puts "      ... task_positions"
  backup.add_task_positions(wunder.task_positions(list[:id]))
  STDERR.puts "      ... subtask_positions"
  backup.add_subtask_positions(wunder.subtask_positions(list[:id]))
end

puts JSON.dump(backup.to_hash)

