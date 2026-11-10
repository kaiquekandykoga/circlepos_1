# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.test_files = FileList["part_*/test_*.rb"]
  t.warning = true
end

task default: :test
