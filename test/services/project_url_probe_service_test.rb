require "test_helper"

class ProjectUrlProbeServiceTest < ActiveSupport::TestCase
  setup do
    @project = projects(:one)
    @project.update_columns(
      demo_url: "https://demo.example.test/",
      repo_url: "https://github.com/example/repo",
      readme_url: nil
    )
  end

  test "ok when both demo and repo reachable" do
    stub_reachable({ @project.demo_url => true, @project.repo_url => true }) do
      result = ProjectUrlProbeService.new(@project).call
      assert result.ok?
      assert_empty result.failures
    end
  end

  test "fails when demo unreachable" do
    stub_reachable({ @project.demo_url => false, @project.repo_url => true }) do
      result = ProjectUrlProbeService.new(@project).call
      refute result.ok?
      assert_equal 1, result.failures.size
      assert_match(/demo URL/, result.failures.first)
    end
  end

  test "fails when repo unreachable" do
    stub_reachable({ @project.demo_url => true, @project.repo_url => false }) do
      result = ProjectUrlProbeService.new(@project).call
      refute result.ok?
      assert_match(/repo URL/, result.failures.first)
    end
  end

  test "fails when both unreachable, reports both" do
    stub_reachable({ @project.demo_url => false, @project.repo_url => false }) do
      result = ProjectUrlProbeService.new(@project).call
      refute result.ok?
      assert_equal 2, result.failures.size
    end
  end

  test "fails when demo url is blank without probing" do
    @project.update_columns(demo_url: nil)
    stub_reachable({ @project.repo_url => true }, fail_on_unstubbed: true) do
      result = ProjectUrlProbeService.new(@project).call
      refute result.ok?
      assert_match(/demo URL/, result.failures.first)
    end
  end

  private

  def stub_reachable(map, fail_on_unstubbed: false)
    @project.define_singleton_method(:url_reachable?) do |url|
      if map.key?(url)
        map[url]
      elsif fail_on_unstubbed
        raise "unexpected url_reachable? call for #{url.inspect}"
      else
        false
      end
    end
    yield
  end
end
