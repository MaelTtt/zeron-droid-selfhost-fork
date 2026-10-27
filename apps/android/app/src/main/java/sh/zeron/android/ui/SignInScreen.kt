package sh.zeron.android.ui

import android.net.Uri
import androidx.browser.customtabs.CustomTabsIntent
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialShapes
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.toShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import sh.zeron.android.R
import sh.zeron.android.core.AppModel

@OptIn(ExperimentalMaterial3ExpressiveApi::class)
@Composable
fun SignInScreen(model: AppModel) {
    val context = LocalContext.current
    val error by model.signInError.collectAsState()
    val orgs by model.orgChoice.collectAsState()
    val client by model.client.collectAsState()
    val connecting by model.serverConnecting.collectAsState()
    val serverError by model.serverError.collectAsState()
    var serverDialog by remember { mutableStateOf(false) }
    var serverUrl by remember { mutableStateOf(model.selfHostUrl ?: "") }
    LaunchedEffect(client) { if (client != null) serverDialog = false }
    Column(
        Modifier.fillMaxSize().safeDrawingPadding().padding(horizontal = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Image(
            painterResource(R.mipmap.ic_launcher_foreground),
            null,
            Modifier.size(148.dp).clip(MaterialShapes.Cookie12Sided.toShape()),
        )
        Spacer(Modifier.height(32.dp))
        Text("Zeron", style = MaterialTheme.typography.displayMedium)
        Spacer(Modifier.height(10.dp))
        Text(
            "Follow and steer your coding agents from anywhere.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(48.dp))
        Button(
            onClick = {
                val url = model.beginSignIn()
                CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(context, Uri.parse(url))
            },
            modifier = Modifier.fillMaxWidth().heightIn(min = ButtonDefaults.MediumContainerHeight),
            shapes = ButtonDefaults.shapes(),
            contentPadding = ButtonDefaults.contentPaddingFor(ButtonDefaults.MediumContainerHeight),
        ) {
            Text("Sign in", style = ButtonDefaults.textStyleFor(ButtonDefaults.MediumContainerHeight))
        }
        Spacer(Modifier.height(12.dp))
        OutlinedButton(
            onClick = { model.startDemo() },
            modifier = Modifier.fillMaxWidth().heightIn(min = ButtonDefaults.MediumContainerHeight),
            shapes = ButtonDefaults.shapes(),
        ) {
            Text("Explore the demo", style = ButtonDefaults.textStyleFor(ButtonDefaults.MediumContainerHeight))
        }
        Spacer(Modifier.height(12.dp))
        OutlinedButton(
            onClick = {
                model.serverError.value = null
                serverDialog = true
            },
            modifier = Modifier.fillMaxWidth().heightIn(min = ButtonDefaults.MediumContainerHeight),
            shapes = ButtonDefaults.shapes(),
        ) {
            Text("Self-hosted server", style = ButtonDefaults.textStyleFor(ButtonDefaults.MediumContainerHeight))
        }
        error?.let {
            Spacer(Modifier.height(20.dp))
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
        }
    }
    orgs?.let { (list, choice) ->
        AlertDialog(
            onDismissRequest = { choice.complete(null) },
            title = { Text("Choose an organization") },
            text = {
                Column {
                    for (org in list) {
                        ListItem(
                            headlineContent = { Text(org.name) },
                            trailingContent = {
                                TextButton(onClick = { choice.complete(org) }) { Text("Open") }
                            },
                        )
                    }
                }
            },
            confirmButton = {},
            dismissButton = { TextButton(onClick = { choice.complete(null) }) { Text("Cancel") } },
        )
    }
    if (serverDialog) {
        AlertDialog(
            onDismissRequest = { if (!connecting) serverDialog = false },
            title = { Text("Self-hosted server") },
            text = {
                Column {
                    Text(
                        "Point this device at your Zeron edge (AUTH_MODE=none). No account needed.",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Spacer(Modifier.height(12.dp))
                    OutlinedTextField(
                        value = serverUrl,
                        onValueChange = {
                            serverUrl = it
                            model.serverError.value = null
                        },
                        singleLine = true,
                        label = { Text("Edge URL") },
                        placeholder = { Text("http://192.168.1.20:8787") },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    serverError?.let {
                        Spacer(Modifier.height(10.dp))
                        Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }
            },
            confirmButton = {
                TextButton(
                    onClick = { model.connectSelfHost(serverUrl) },
                    enabled = !connecting,
                ) { Text(if (connecting) "Connecting…" else "Connect") }
            },
            dismissButton = {
                TextButton(onClick = { serverDialog = false }, enabled = !connecting) { Text("Cancel") }
            },
        )
    }
}
