import Foundation
import MCP

enum MCPToolCatalog {
    static func tools() throws -> [Tool] {
        let text: [String: Any] = ["type": "string"]
        let uuid: [String: Any] = ["type": "string", "format": "uuid"]
        let day: [String: Any] = ["type": "string", "pattern": #"^\d{4}-\d{2}-\d{2}$"#]
        let boolean: [String: Any] = ["type": "boolean"]
        let integer: [String: Any] = ["type": "integer"]
        func nullable(_ schema: [String: Any]) -> [String: Any] { ["anyOf": [schema, ["type": "null"]]] }
        func object(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
            ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
        }
        let fields = object([
            "title": ["type": "string", "minLength": 1, "maxLength": 500],
            "notes": text, "listID": nullable(uuid), "day": nullable(day),
            "startMinute": nullable(["type": "integer", "minimum": 0, "maximum": 1439]),
            "durationMinutes": ["type": "integer", "minimum": 15, "maximum": 1440, "multipleOf": 15],
            "timeZoneID": ["type": "string", "description": "IANA timezone, e.g. Asia/Shanghai. Defaults to the Mac timezone."],
            "priority": ["type": "integer", "enum": [0, 1, 2, 3]],
            "repeatRule": object(["kind": ["type": "string", "enum": ["never", "daily", "weekdays", "weekly"]],
                                   "weekdays": ["type": "array", "items": ["type": "integer", "minimum": 1, "maximum": 7],
                                                "description": "Gregorian Sunday=1, Monday=2; required for weekly."],
                                   "until": nullable(day)], required: ["kind"]),
            "reminderMinutesBefore": nullable(["type": "integer", "minimum": 0, "maximum": 10080]),
            "allDayReminderMinute": ["type": "integer", "minimum": 0, "maximum": 1439]
        ])
        func tool(_ name: String, _ description: String, _ schema: [String: Any], readOnly: Bool = false, idempotent: Bool = false) throws -> Tool {
            Tool(name: name, description: description, inputSchema:
                    try JSONDecoder().decode(Value.self, from: JSONSerialization.data(withJSONObject: schema)),
                 annotations: .init(readOnlyHint: readOnly, destructiveHint: !readOnly, idempotentHint: idempotent, openWorldHint: false))
        }
        return try [
            tool("get_status", "Check Daydo login, system-iCloud storage mode, local day and timezone. Does not disclose tasks.", object([:]), readOnly: true),
            tool("list_lists", "Read lists, optionally including archived lists.", object(["includeArchived": boolean]), readOnly: true),
            tool("create_list", "Create a list. Reuse requestId only for an identical retry.", object(["name": text, "color": text, "requestId": text], required: ["name"])),
            tool("update_list", "Rename, color, sort or archive a list, retaining its tasks. Requires current revision.", object([
                "listId": uuid, "expectedRevision": uuid, "name": text, "color": text, "order": ["type": "number"], "isArchived": boolean
            ], required: ["listId", "expectedRevision"])),
            tool("list_tasks", "Query task occurrences in an inclusive date range, maximum 366 days. Defaults to today. Undated tasks require includeUndated. Returns items, total and nextOffset. Occurrence originalDay identifies repeat instances; fields.day may differ after a move.",
                 object(["from": day, "through": day, "listId": uuid, "completed": boolean, "query": text, "includeUndated": boolean,
                         "limit": ["type": "integer", "minimum": 1, "maximum": 200], "offset": integer]), readOnly: true),
            tool("get_task", "Read the task series and optional occurrence override. Use the override revision when present.", object([
                "taskId": uuid, "occurrenceDay": day
            ], required: ["taskId"]), readOnly: true),
            tool("create_task", "Create a task. fields.title is required; omitted fields use defaults. Use requestId for retry deduplication.",
                 object(["fields": fields, "requestId": text], required: ["fields"])),
            tool("update_task", "Patch task fields; omitted fields stay unchanged, null clears optional fields. Requires expectedRevision. Repeat edits require occurrenceDay and scope occurrence or future. Future splits the series and returns a new task ID, preserving past history.",
                 object(["taskId": uuid, "expectedRevision": uuid, "occurrenceDay": day,
                         "scope": ["type": "string", "enum": ["task", "occurrence", "future"]], "fields": fields],
                        required: ["taskId", "expectedRevision", "fields"])),
            tool("set_task_completion", "Set completed=true or false; retries never toggle. Repeat tasks require occurrenceDay, single tasks omit it.",
                 object(["taskId": uuid, "occurrenceDay": day, "completed": boolean], required: ["taskId", "completed"]), idempotent: true)
        ]
    }
}
