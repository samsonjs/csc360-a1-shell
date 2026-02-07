require "minitest/autorun"
require "etc"
require "timeout"
$LOAD_PATH.unshift(File.expand_path("..", __dir__))
require_relative "../shell/job_control"
require_relative "../shell/logger"

class ShellTest < Minitest::Test
  TRIVIAL_SHELL_SCRIPT = "#!/bin/sh\ntrue".freeze

  A1_PATH = ENV.fetch("A1_PATH", "./a1").freeze

  def setup
    FileUtils.mkdir_p("test_bin")
  end

  def teardown
    FileUtils.rm_rf("test_bin")
  end

  def unique_shell_script(code)
    "#!/bin/sh\necho '#{code}'"
  end

  def test_expands_environment_variables
    assert_equal Dir.home, `#{A1_PATH} -c 'echo $HOME'`.chomp
    assert_equal Dir.home, `#{A1_PATH} -c 'echo ${HOME}'`.chomp
    assert_equal "#{Dir.home} #{Dir.home}", `#{A1_PATH} -c 'echo ${HOME} ${HOME}'`.chomp
  end

  def test_fails_on_unknown_variables
    assert_equal false, system("#{A1_PATH} -c 'echo $DEFINITELY_DOES_NOT_EXIST' 2>/dev/null")
  end

  def test_expands_tilde
    assert_equal Dir.home, `#{A1_PATH} -c 'echo ~'`.chomp
  end

  def test_splits_words
    assert_equal "a b c", `#{A1_PATH} -c 'echo a b c'`.chomp
  end

  def test_respects_double_quotes
    assert_equal "a b", `#{A1_PATH} -c 'echo \"a b\"'`.chomp
  end

  def test_respects_escaped_double_quote_in_double_quotes
    assert_equal "a\"b", `#{A1_PATH} -c 'echo \"a\\\"b\"'`.chomp
  end

  def test_respects_single_quotes
    assert_equal "a b", `#{A1_PATH} -c \"echo 'a b'\"`.chomp
  end

  def test_respects_backslash_escaping
    assert_equal "a b", `#{A1_PATH} -c 'echo a\\ b'`.chomp
  end

  def test_expands_globs
    File.write("globtest_a.txt", TRIVIAL_SHELL_SCRIPT)
    File.write("globtest_b.txt", TRIVIAL_SHELL_SCRIPT)
    output = `#{A1_PATH} -c 'echo globtest_*.txt'`.chomp.split
    assert_equal ["globtest_a.txt", "globtest_b.txt"], output.sort
  ensure
    FileUtils.rm_f("globtest_a.txt")
    FileUtils.rm_f("globtest_b.txt")
  end

  def test_does_not_reglob_expanded_paths
    File.write("globspecial_a.txt", TRIVIAL_SHELL_SCRIPT)
    File.write("globspecial_[a].txt", TRIVIAL_SHELL_SCRIPT)
    output = `#{A1_PATH} -c 'echo globspecial_*.txt'`.chomp.split
    assert_equal ["globspecial_[a].txt", "globspecial_a.txt"], output.sort
  ensure
    FileUtils.rm_f("globspecial_a.txt")
    FileUtils.rm_f("globspecial_[a].txt")
  end

  def test_does_not_expand_escaped_dollar
    assert_equal "$HOME", `#{A1_PATH} -c 'echo \\$HOME'`.chomp
  end

  def test_expands_brace_expansion
    assert_equal "a b", `#{A1_PATH} -c 'echo {a,b}'`.chomp
  end

  def test_expands_command_substitution_backticks
    assert_equal "hi", %x(#{A1_PATH} -c 'echo `echo hi`').chomp
  end

  def test_expands_command_substitution_dollar_paren
    assert_equal "hi", `#{A1_PATH} -c 'echo $(echo hi)'`.chomp
  end

  def test_expands_command_substitution_with_escaped_quote
    assert_equal "a\"b", `#{A1_PATH} -c 'echo $(printf \"%s\" \"a\\\"b\")'`.chomp
  end

  def test_expands_arithmetic
    assert_equal "3", `#{A1_PATH} -c 'echo $((1 + 2))'`.chomp
  end

  def test_expands_arithmetic_with_variables
    assert_equal "3", `A1_NUM=2 #{A1_PATH} -c 'echo $((A1_NUM + 1))'`.chomp
  end

  def test_expands_tilde_user
    user = Etc.getlogin
    skip "no login user" unless user
    assert_equal Dir.home(user), `#{A1_PATH} -c 'echo ~#{user}'`.chomp
  end

  def test_expands_parameter_default_value
    assert_equal "fallback", `#{A1_PATH} -c 'echo ${A1_UNSET_VAR:-fallback}'`.chomp
  end

  def test_expands_parameter_default_value_with_variable_reference
    assert_equal Dir.home, `#{A1_PATH} -c 'echo ${A1_UNSET_VAR:-$HOME}'`.chomp
  end

  def test_expands_parameter_default_value_with_command_substitution
    assert_equal "hi", `#{A1_PATH} -c 'echo ${A1_UNSET_VAR:-$(echo hi)}'`.chomp
  end

  def test_does_not_expand_escaped_command_substitution_dollar_paren_in_double_quotes
    assert_equal "$(echo hi)", `#{A1_PATH} -c 'echo "\\$(echo hi)"'`.chomp
  end

  def test_does_not_expand_escaped_command_substitution_backticks_in_double_quotes
    assert_equal "`echo hi`", %x(#{A1_PATH} -c 'echo "\\`echo hi\\`"').chomp
  end

  #################################
  ### Execution and job control ###
  #################################

  def test_background_job
    output = `#{A1_PATH} -c 'bg echo hello'`.gsub(/\e\[([;\d]+)?m/, "")
    pid = /\(pid (\d+)\)/.match(output)[1]
    lines = output.split("\n").map(&:chomp)
    assert_equal ["Running job 1 (pid #{pid}) in background", "hello"], lines.sort
  end

  def test_resolves_executables_with_absolute_paths
    output = `#{A1_PATH} -c '/usr/bin/which -a which'`.lines.map(&:chomp)
    assert_includes output, "/usr/bin/which"
  end

  def test_resolves_executables_with_relative_paths
    File.write("test_bin/something", TRIVIAL_SHELL_SCRIPT)
    File.chmod(0o755, "test_bin/something")
    assert system("#{A1_PATH} -c ./test_bin/something")
  end

  def test_resolves_executables_in_absolute_paths
    output = `#{A1_PATH} -c 'which -a which'`.lines.map(&:chomp)
    assert_includes output, "/usr/bin/which"
  end

  def test_resolves_executables_in_relative_paths
    code = rand(1_000_000).to_s
    File.write("test_bin/definitely_executable", unique_shell_script(code))
    File.chmod(0o755, "test_bin/definitely_executable")
    actual = `PATH="./test_bin:$PATH" #{A1_PATH} -c definitely_executable`.chomp
    assert_equal code, actual
  end

  def test_does_not_resolve_non_executable_files_in_path
    File.write("test_bin/definitely_not_executable", TRIVIAL_SHELL_SCRIPT)
    File.chmod(0o644, "test_bin/definitely_not_executable")
    actual = system("PATH=\"./test_bin:$PATH\" #{A1_PATH} -c definitely_not_executable 2>/dev/null")
    assert_equal false, actual
  end

  def test_refreshes_readline_after_bg_execution
    called = false
    job_control = Shell::JobControl.new(
      logger: Shell::Logger.instance,
      refresh_line: -> { called = true }
    )
    previous = job_control.trap_sigchld
    begin
      job_control.exec_command("echo", ["hello"], background: true)
      Timeout.timeout(2) do
        sleep 0.01 until called
      end
      assert called
    ensure
      Signal.trap("CHLD", previous)
    end
  end

  #########################
  ### Built-in commands ###
  #########################

  def test_builtin_cd_no_args
    assert_equal Dir.home, `#{A1_PATH} -c 'cd; echo $PWD'`.strip
  end

  def test_builtin_cd
    assert_equal File.join(Dir.pwd, "blah"), `#{A1_PATH} -c 'mkdir -p blah; cd blah; echo $PWD; cd ..; rm -rf blah'`.strip
  end

  def test_builtin_cd_dash
    assert_equal Dir.pwd, `#{A1_PATH} -c 'mkdir -p blah; cd blah; cd -; rm -rf blah; echo $PWD'`.strip
  end

  def test_builtin_cd_parent
    assert_equal Dir.pwd, `#{A1_PATH} -c 'mkdir -p blah; cd blah; cd ..; rm -rf blah; echo $PWD'`.strip
  end

  def test_builtin_pwd
    assert_equal Dir.pwd, `#{A1_PATH} -c pwd`.chomp

    shell_path = File.expand_path(A1_PATH, Dir.pwd)
    assert_equal "/usr/bin", `cd /usr/bin && '#{shell_path}' -c pwd`.chomp
  end
end
