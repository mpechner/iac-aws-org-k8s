# First Let’s Encrypt with Route 53

I have used other people’s setups that just handle Let’s Encrypt, but never set it up on my own. The following is the reading list from ChatGPT.

---

# Setting Up Let’s Encrypt with Route 53 DNS Validation

## Official Documentation & Guides

1. **Certbot DNS Route53 Plugin (Let’s Encrypt official client)**
   - Docs on using Certbot with Route 53 for DNS-01 challenge automation:  
     https://certbot.eff.org/docs/using.html#dns-plugins
   - Plugin GitHub repo:  
     https://github.com/certbot/certbot/tree/main/certbot-dns-route53

2. **Let’s Encrypt - DNS-01 Challenge**  
   Explanation of DNS validation using TXT records:  
   https://letsencrypt.org/docs/challenge-types/#dns-01-challenge

3. **AWS Route 53 API Documentation**  
   API Reference for managing Route 53 records (used by Certbot plugin):  
  https://docs.aws.amazon.com/Route53/latest/APIReference/Welcome.html

  https://registry.terraform.io/providers/vancluever/acme/latest/docs


https://letsencrypt.org/


---

## Tutorials & Community Guides

4. **How to Use Certbot with Route 53 DNS for Let’s Encrypt**  
   Updated step-by-step guide including IAM permissions and automation:  
   https://johnrix.medium.com/automating-dns-challenge-based-letsencrypt-certificates-with-aws-route-53-8ba799dd207b

https://www.opencredo.com/blogs/letsencrypt-terraform

https://github.com/opencredo/letsencrypt-terraform

---

## Key Setup Steps Summary

- Create an **IAM user or role** with permissions:
  - `route53:ChangeResourceRecordSets`
  - `route53:ListHostedZones`
- Install **Certbot** and the **Route 53 DNS plugin**.
- Configure AWS credentials (environment variables, AWS CLI profile, or instance role).
- Run certbot with `--dns-route53` plugin to automate DNS TXT record creation/removal.
- Automate renewal with a cron job or CI/CD pipeline.

---

If you'd like, I can provide sample commands or Terraform snippets to get you started — just ask!
