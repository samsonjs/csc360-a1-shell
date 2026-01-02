require "minitest/autorun"

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
    skip "unimplemented"
  end

  #########################
  ### Built-in commands ###
  #########################

  def test_builtin_cd_no_args
    skip "cannot easily implement without sequencing with ; or &&"
  end

  def test_builtin_cd
    skip "cannot easily implement without sequencing with ; or &&"
  end

  def test_builtin_cd_dash
    skip "cannot easily implement without sequencing with ; or &&"
  end

  def test_builtin_cd_parent
    skip "cannot easily implement without sequencing with ; or &&"
  end

  def test_builtin_pwd
    assert_equal Dir.pwd, `#{A1_PATH} -c pwd`.chomp

    shell_path = File.expand_path(A1_PATH, Dir.pwd)
    assert_equal "/usr/bin", `cd /usr/bin && '#{shell_path}' -c pwd`.chomp
  end
end
