<?php
/* Native DNAT rules: web traffic to router Caddy, Plex clients to the VM. */
require_once('/usr/local/opnsense/mvc/script/load_phalcon.php');
use OPNsense\Core\Config;
use OPNsense\Firewall\DNat;
$input = json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR);
$action = $input['action'];
if (!in_array($action, ['ingress-plan','ingress-apply'], true)) throw new RuntimeException('Unexpected ingress action');
$config = Config::getInstance();
$config->lock();
$changes = [];
try {
    $model = new DNat();
    foreach ([80=>'10.69.0.1',443=>'10.69.0.1',32400=>'10.69.0.18'] as $port=>$target) {
        $description = $port === 32400 ? 'Plex Port Forward' : 'nixflix managed Caddy WAN ' . $port;
        $match = null;
        foreach ($model->rule->iterateItems() as $node) {
            if ((string)$node->descr === $description) {
                if ($match !== null) throw new RuntimeException('Duplicate managed port forward');
                $match = $node;
            } elseif ((string)$node->interface === 'wan' && (string)$node->destination->port === (string)$port && (string)$node->disabled !== '1') {
                throw new RuntimeException('Existing conflicting WAN port forward requires review');
            }
        }
        $values = ['disabled'=>'0','nordr'=>'0','interface'=>'wan','ipprotocol'=>'inet',
            'protocol'=>'tcp','target'=>$target,'local-port'=>(string)$port,'descr'=>$description,
            'pass'=>'pass','associated-rule-id'=>'','natreflection'=>'disable'];
        if ($match === null) {
            $match = $model->rule->Add();
            $match->sequence = (string)$port;
            $changes[] = 'add ' . $description;
        }
        foreach ($values as $field=>$value) if ((string)$match->{$field} !== $value) {
            $match->{$field} = $value;
            $changes[] = $description . ': ' . $field;
        }
        foreach (['network'=>'','port'=>'','not'=>'0'] as $field=>$value) if ((string)$match->source->{$field} !== $value) {
            $match->source->{$field} = $value;
            $changes[] = $description . ': source.' . $field;
        }
        foreach (['network'=>'wanip','port'=>(string)$port,'not'=>'0'] as $field=>$value) if ((string)$match->destination->{$field} !== $value) {
            $match->destination->{$field} = $value;
            $changes[] = $description . ': destination.' . $field;
        }
    }
    $messages = $model->performValidation();
    if (count($messages)) {
        $errors=[]; foreach($messages as $message)$errors[]=$message->getField().': '.(string)$message;
        throw new RuntimeException(implode('; ',$errors));
    }
    if ($action === 'ingress-apply' && count($changes)) {
        $directory='/conf/nixflix-https-backups';
        if (!is_dir($directory)) mkdir($directory,0700);
        $backup=$directory.'/ingress-'.gmdate('Ymd-His').'-'.bin2hex(random_bytes(3)).'.xml';
        if (!copy('/conf/config.xml',$backup)||!chmod($backup,0600)) throw new RuntimeException('Backup failed');
        $model->serializeToConfig();
        $config->save('Nixflix WAN HTTPS and Plex remote access');
    }
} finally { $config->unlock(); }
echo json_encode(['action'=>$action,'changes'=>$changes,'backup'=>$backup??null],JSON_PRETTY_PRINT)."\n";
if ($action === 'ingress-apply' && count($changes)) {
    passthru('/usr/local/sbin/configctl filter reload', $code);
    if ($code !== 0) throw new RuntimeException('Native filter reload failed');
}
