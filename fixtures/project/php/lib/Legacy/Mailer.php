<?php

/**
 * Legacy mail sender, autoloaded through the PSR-0 map.
 *
 * PSR-0 turns underscores in the class name into directory separators,
 * so `Legacy_Mailer` is found at `lib/Legacy/Mailer.php`.
 */
class Legacy_Mailer
{
    private string $from;

    public function __construct(string $from)
    {
        $this->from = $from;
    }

    public function send(string $to, string $subject, string $body): bool
    {
        return mail($to, $subject, $body, 'From: ' . $this->from);
    }
}
