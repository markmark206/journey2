defmodule Journey.Test.Sweeper do
  use Journey.RepoCase

  require Logger

  @tag timeout: 30_000
  test "just giving background sweeper a bit of time to run" do
    # This test doesn't do much, just gives the sweeper a bit of time to just hang out.

    sleep_time = 20
    Logger.info("letting the sweeper run in the background for a bit (#{sleep_time} seconds)...")
    :timer.sleep(sleep_time * 1_000)
    Logger.info("... exiting")
  end
end
