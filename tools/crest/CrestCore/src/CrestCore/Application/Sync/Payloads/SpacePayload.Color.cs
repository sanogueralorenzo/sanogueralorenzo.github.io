using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

internal sealed partial record SpacePayload {
    #region Actions - Colors

    internal static BrandColor Color(JsonNode? node) {
        var value = new SyncPayloadReader(node, SyncPayloadForm.Journal);
        return new(Unit(value.Number("red")), Unit(value.Number("green")), Unit(value.Number("blue")),
            Unit(value.OptionalNumber("alpha") ?? 1));
    }

    private static double Unit(double value) => Math.Clamp(value, 0, 1);

    #endregion
}
