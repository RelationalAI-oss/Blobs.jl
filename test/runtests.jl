using ReTestItems
using Blobs

ReTestItems.runtests(Blobs)

@testitem "Tests also work with BOUNDSCHECK_ON_DEREF_ENABLED toggled" begin
    using Blobs

    project_dir = dirname(@__DIR__)
    toggled_value = !Blobs.BOUNDSCHECK_ON_DEREF_ENABLED

    julia_code = """
        using Preferences
        # Preference must be set before using Blobs
        set_preferences!(
            "Blobs",
            "BLOBS_BOUNDSCHECK_ON_DEREF_ENABLED" => $toggled_value;
            force=true
        )

        using ReTestItems
        using Blobs

        # Verify the preference was actually toggled
        @assert Blobs.BOUNDSCHECK_ON_DEREF_ENABLED == $toggled_value "Preference toggle failed"

        ReTestItems.runtests(Blobs)
        """

    cmd = Cmd([
        "julia",
        "--project=$project_dir",
        "--startup-file=no",
        "-e",
        julia_code
    ])

    @test success(run(cmd))
end
