# Manage Microsoft Graph Permissions for Managed Identities through Graph Explorer

Managed identities are represented in Microsoft Entra ID as service principals. Microsoft Graph application permissions are granted to managed identities by creating app-role assignments.

> **Warning:** Creating or deleting an app-role assignment takes effect without a separate confirmation prompt. Verify all object IDs and permission names before submitting a request.

## Prerequisites

Sign in to Graph Explorer with an appropriately privileged Microsoft Entra account.

Grant Graph Explorer the following delegated permissions under **Modify permissions**:

- `Application.Read.All`

- `AppRoleAssignment.ReadWrite.All`

The signed-in user must also have a supported Microsoft Entra role. For assigning Microsoft Graph application permissions, **Privileged Role Administrator** is the least-privileged supported built-in role.

Collect the following information:

- `MANAGED_IDENTITY_OBJECT_ID`: Object (principal) ID of the managed identity

- `RESOURCE_SERVICE_PRINCIPAL_ID`: Object ID of the target API's service principal

- `APP_ROLE_ID`: ID of the application permission

- `APP_ROLE_ASSIGNMENT_ID`: ID of an existing assignment, required when deleting it

Use the managed identity's **Object (principal) ID**, not its Application or Client ID.

## Verify the managed identity

Run the following request:

```http

GET https://graph.microsoft.com/v1.0/servicePrincipals/{MANAGED_IDENTITY_OBJECT_ID}?$select=id,appId,displayName,servicePrincipalType

```

Verify the following properties in the response:

- `id` matches the managed identity's Object ID.

- `displayName` identifies the expected Azure resource or user-assigned managed identity.

- `servicePrincipalType` is `ManagedIdentity`.

Example:

```json

{

  "id": "MANAGED_IDENTITY_OBJECT_ID",

  "appId": "MANAGED_IDENTITY_CLIENT_ID",

  "displayName": "my-managed-identity",

  "servicePrincipalType": "ManagedIdentity"

}

```

## Add a permission

### Retrieve the Microsoft Graph service principal and application roles

The application ID of Microsoft Graph is:

```text

00000003-0000-0000-c000-000000000000

```

Retrieve the tenant-specific Microsoft Graph service principal and its application roles:

```http

GET https://graph.microsoft.com/v1.0/servicePrincipals(appId='00000003-0000-0000-c000-000000000000')?$select=id,displayName,appRoles

```

From the response:

1. Copy the top-level `id`. This is the `RESOURCE_SERVICE_PRINCIPAL_ID`.

2. Search `appRoles` for the required permission, such as `"value": "User.Read.All"`.

3. Confirm that its `allowedMemberTypes` property contains `"Application"`.

4. Copy the matching role's `id`. This is the `APP_ROLE_ID`.

Example application-role definition:

```json

{

  "id": "APP_ROLE_ID",

  "value": "User.Read.All",

  "displayName": "Read all users' full profiles",

  "allowedMemberTypes": [

    "Application"

  ],

  "isEnabled": true

}

```

Do not use the ID of the delegated permission. Managed identities use application permissions.

### Create the app-role assignment

In Graph Explorer, select the `POST` method and use:

```http

https://graph.microsoft.com/v1.0/servicePrincipals/{MANAGED_IDENTITY_OBJECT_ID}/appRoleAssignments

```

Set the request body to:

```json

{

  "principalId": "MANAGED_IDENTITY_OBJECT_ID",

  "resourceId": "RESOURCE_SERVICE_PRINCIPAL_ID",

  "appRoleId": "APP_ROLE_ID"

}

```

The properties have the following meanings:

| Property | Value |

|---|---|

| `principalId` | Object ID of the managed identity service principal |

| `resourceId` | Object ID of the service principal that exposes the permission |

| `appRoleId` | ID of the application permission being assigned |

A successful request returns:

```http

201 Created

```

## List assigned permissions

List the managed identity's app-role assignments:

```http

GET https://graph.microsoft.com/v1.0/servicePrincipals/{MANAGED_IDENTITY_OBJECT_ID}/appRoleAssignments?$select=id,appRoleId,resourceId,resourceDisplayName,principalDisplayName,createdDateTime

```

Example assignment:

```json

{

  "id": "APP_ROLE_ASSIGNMENT_ID",

  "appRoleId": "APP_ROLE_ID",

  "resourceId": "RESOURCE_SERVICE_PRINCIPAL_ID",

  "resourceDisplayName": "Microsoft Graph",

  "principalDisplayName": "my-managed-identity",

  "createdDateTime": "2026-10-28T12:00:00Z"

}

```

The two ID properties serve different purposes:

- `id` identifies this specific assignment. Use it to delete the assignment.

- `appRoleId` identifies the permission definition, such as `User.Read.All`.

## Delete a permission

### Find the assignment ID

Run the list request:

```http

GET https://graph.microsoft.com/v1.0/servicePrincipals/{MANAGED_IDENTITY_OBJECT_ID}/appRoleAssignments?$select=id,appRoleId,resourceId,resourceDisplayName

```

Identify the assignment using its `resourceDisplayName`, `resourceId`, and `appRoleId`.

Copy the assignment's top-level `id` as the `APP_ROLE_ASSIGNMENT_ID`.

> **Important:** Do not use the `appRoleId` in the DELETE request. The DELETE request requires the assignment's own `id`.

### Delete the app-role assignment

In Graph Explorer, select the `DELETE` method and use:

```http

https://graph.microsoft.com/v1.0/servicePrincipals/{MANAGED_IDENTITY_OBJECT_ID}/appRoleAssignments/{APP_ROLE_ASSIGNMENT_ID}

```

Do not include a request body.

A successful deletion returns:

```http

204 No Content

```

## Verify the change

List the managed identity's assignments again:

```http
GET https://graph.microsoft.com/v1.0/servicePrincipals/{MANAGED_IDENTITY_OBJECT_ID}/appRoleAssignments?$select=id,appRoleId,resourceId,resourceDisplayName
```

After adding a permission, confirm that the expected assignment appears.
After deleting a permission, confirm that the assignment no longer appears.
Microsoft Entra directory replication can delay when a new or deleted assignment becomes visible. Existing managed identity access tokens can also continue to contain the previous permissions until they expire. Obtain a new access token before testing the changed permissions.

## Common errors

| Error                                         | Likely cause                                                                                                   |
| --------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| `403 Authorization_RequestDenied`             | Graph Explorer lacks the required permissions, or the signed-in user lacks an appropriate Microsoft Entra role |
| `400 Permission being assigned was not found` | The `appRoleId` does not belong to the specified resource service principal                                    |
| `400 New assignment must be unique`           | The permission is already assigned to the managed identity                                                     |
| `404 Request_ResourceNotFound`                | The managed identity Object ID or app-role assignment ID is incorrect                                          |
| Permission still appears after deletion       | Directory replication has not completed                                                                        |
| Access continues after deletion               | The workload is still using an access token issued before the permission was removed                           |

